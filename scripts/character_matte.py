"""Source-resolution character matting. Never applies the UI color-key to clothes.

Uses an exterior-connected trimap, GrabCut, and foreground color reconstruction
in a narrow boundary band. White eyes/hat spots and opaque interior pixels stay
intact. Inputs are the supplied artwork, not generated replacements.
"""
import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFilter


def nearest_color(rgb, known):
    _, labels = cv2.distanceTransformWithLabels(
        (~known).astype('uint8'), cv2.DIST_L2, 5, labelType=cv2.DIST_LABEL_PIXEL)
    return rgb[known][np.maximum(labels - 1, 0)]


def character_cutout(image):
    rgba = np.array(image.convert('RGBA'))
    if rgba[:, :, 3].min() < 255:
        return image.convert('RGBA')
    rgb = rgba[:, :, :3].copy()
    color = rgb.astype('float32')
    neutral = (color.max(2) - color.min(2) < 7) & (color.min(2) > 238)
    # The source's gray ground shadow is not part of the shoes or stockings.
    foot_zone = np.indices(neutral.shape)[0] > neutral.shape[0] * .84
    neutral |= foot_zone & (color.max(2) - color.min(2) < 18) & (color.min(2) > 170)
    _, labels = cv2.connectedComponents(neutral.astype('uint8'), connectivity=8)
    border = np.unique(np.concatenate((labels[0], labels[-1], labels[:, 0], labels[:, -1])))
    background = np.isin(labels, border[border != 0])
    silhouette = (~background).astype('uint8')
    inner = cv2.erode(silhouette, np.ones((5, 5), 'uint8')) > 0
    outer = cv2.dilate(silhouette, np.ones((7, 7), 'uint8')) > 0
    trimap = np.full(silhouette.shape, cv2.GC_PR_BGD, dtype='uint8')
    trimap[silhouette > 0] = cv2.GC_PR_FGD
    trimap[inner] = cv2.GC_FGD
    trimap[~outer] = cv2.GC_BGD
    trimap[[0, -1], :] = cv2.GC_BGD
    trimap[:, [0, -1]] = cv2.GC_BGD
    cv2.setRNGSeed(0)
    cv2.grabCut(rgb, trimap, None, np.zeros((1, 65)), np.zeros((1, 65)), 3, cv2.GC_INIT_WITH_MASK)
    mask = np.isin(trimap, [cv2.GC_FGD, cv2.GC_PR_FGD]).astype('uint8')
    mask = cv2.medianBlur(mask, 3)
    # Remove isolated checker residue, but retain small authored flowers/sparkles.
    count, components, stats, _ = cv2.connectedComponentsWithStats(mask, 8)
    for i in range(1, count):
        if stats[i, cv2.CC_STAT_AREA] < 5:
            mask[components == i] = 0
    inside = cv2.distanceTransform(mask, cv2.DIST_L2, 5)
    outside = cv2.distanceTransform(1 - mask, cv2.DIST_L2, 5)
    foreground = inside >= 3
    backdrop = outside >= 3
    if not foreground.any() or not backdrop.any():
        raise ValueError('Character crop has no stable foreground/background')
    f = nearest_color(color, foreground)
    b = nearest_color(color, backdrop)
    delta = f - b
    coverage = np.clip(((color - b) * delta).sum(2) / np.maximum((delta * delta).sum(2), 25), 0, 1)
    edge = (inside < 3) & (outside <= 2)
    alpha = mask.astype('float32')
    alpha[edge] = coverage[edge]
    # Limit fractional coverage to the true contour, not a blurred outer halo.
    alpha[outside > 2] = 0
    alpha[alpha < .035] = 0
    alpha[alpha > .97] = 1
    reconstructed = (color - (1 - alpha[:, :, None]) * b) / np.maximum(alpha[:, :, None], .05)
    result = color.copy()
    partial = edge & (alpha > 0) & (alpha < 1)
    result[partial] = np.clip(reconstructed[partial], 0, 255)
    result[alpha == 0] = 0
    return Image.fromarray(np.dstack((result.astype('uint8'), np.rint(alpha * 255).astype('uint8'))))


def resample_rgba(pixels, transform):
    """Interpolate premultiplied color, so transparent pixels cannot darken edges."""
    rgba = pixels.astype('float32') / 255
    rgba[:, :, :3] *= rgba[:, :, 3:4]
    out = np.clip(transform(rgba), 0, 1)
    out[:, :, :3] /= np.maximum(out[:, :, 3:4], 1e-6)
    out[out[:, :, 3] < 1 / 255] = 0
    return np.rint(np.clip(out, 0, 1) * 255).astype('uint8')


def warp_rgba(pixels, matrix, size=(256, 256), flags=cv2.INTER_CUBIC):
    return resample_rgba(pixels, lambda rgba: cv2.warpAffine(rgba, matrix, size, flags=flags))


def remap_rgba(pixels, x, y, interpolation=cv2.INTER_LINEAR):
    return resample_rgba(pixels, lambda rgba: cv2.remap(rgba, x, y, interpolation))


def soften_symbiosis_emission(image, source_sheet, box):
    """Keep the authored central figure opaque; derive the surrounding gold glow
    from chroma instead of retaining the sheet's white checker as a solid badge.
    Polygon coordinates refer to the existing 403 x 403 symbiosis source crop.
    """
    a = np.array(image.convert('RGBA'))
    core = Image.new('L', image.size)
    ImageDraw.Draw(core).polygon([(200,12),(236,24),(264,62),(291,110),(295,145),
        (278,164),(277,189),(272,220),(251,245),(260,273),(265,297),(274,329),
        (255,346),(234,348),(233,369),(208,373),(184,372),(165,368),(162,347),
        (142,339),(147,295),(147,272),(155,247),(123,223),(124,199),(105,169),
        (110,140),(129,111),(135,76),(161,38)], fill=255)
    protection = np.array(core.filter(ImageFilter.GaussianBlur(3))).astype('float32') / 255
    rgb = np.array(source_sheet.crop(box).convert('RGB')).astype('float32')
    emission = np.clip((rgb.max(2) - rgb.min(2) - 5) / 75, 0, 1)
    coverage = np.maximum(protection * a[:,:,3]/255, emission)
    source = np.array(source_sheet.convert('RGB')).astype('float32')
    sx = np.clip((np.median(source[:8], axis=(0,2))-249)/5, -1, 1)
    sy = np.clip((np.median(source[:,:8], axis=(1,2))-249)/5, -1, 1)
    x0,y0,x1,y1 = box
    checker = 249+5*sy[y0:y1,None]*sx[None,x0:x1]
    rgb += ((249-checker)*(1-coverage))[:,:,None]
    # Decontaminate white behind the golden semi-transparent light as well.
    clean = (rgb - (1 - coverage[:, :, None]) * 248) / np.maximum(coverage[:, :, None], .05)
    blend = (1 - protection)[:, :, None]
    a[:, :, :3] = np.clip(rgb * (1-blend) + clean * blend, 0, 255).astype('uint8')
    a[:, :, 3] = np.rint(255 * coverage).astype('uint8')
    a[a[:, :, 3] < 4] = 0
    # The baked glow also modulates the checker. Keep figure/flower detail and
    # low-pass only weak emission, in premultiplied color, to remove that grid.
    weight = ((1-protection)*np.clip((.8-emission)/.6,0,1))[:,:,None]
    a = resample_rgba(a, lambda rgba: rgba*(1-weight)+cv2.GaussianBlur(rgba,(0,0),8)*weight)
    return Image.fromarray(a)
