export const GARDEN_SOLUTIONS:Record<string,string[]>={
 '1-1':['f:0:0','!grow:root:down','f:0:2','f:0:0','!retract:root','!grow:root:right','f:3:0','!repair'],
 '1-2':['f:1:1','!grow:root:up','!grow:root:right','!grow:root:right','!grow:root:down','f:4:1','!repair'],
 '1-3':['m:garden:0:0','!turn:garden','f:0:-4','!repair'],
 '1-4':['f:-3:0','!use:hold','!switch','f:3:5','!switch','f:-3:5','!use:latch','f:-2:5','!take:bell','f:-4:0','!use:home','!switch','f:-4:0','!switch','!follow','f:-9:0','!repair'],
 '2-1':['f:0:4','!take:dew','m:float:0:0','!use:care','!valve:water','f:4:0','!repair'],
 '2-2':['f:4:3','!take:mirrorB','f:1:0','!drop:mirrorB:f:1:0','!angle:mirrorB','f:1:1','!angle:mirrorA','f:4:0','!repair'],
 '2-3':['m:stage:0:0','!switch','f:-4:0','!beat','!beat','!beat','!switch','f:0:-4','!use:latch','!switch','f:1:-4','!switch','!repair'],
 '2-4':['m:boat:0:0','!use:plant','!use:invite','!turn:boat','!use:invite','f:10:0','!repair'],
 '3-1':['!switch','!take:lamp','f:3:5','!switch','f:3:0','!use:window','!switch','f:4:0','!switch','!repair'],
 '3-2':['f:-2:0','!take:sunPost','f:0:0','!drop:sunPost:f:0:0','f:-2:1','!take:moonPost','f:3:-1','!drop:moonPost:f:3:-1','f:-1:1','!freeze','f:-1:0','!valve:mode','f:3:4','!repair'],
 '3-3':['f:1:-4','!grow:root:right','!grow:root:right','!grow:root:right','!grow:root:down','m:lift:0:0','!valve:lift','f:8:0','!take:dew','m:lift:0:0','!valve:lift','f:1:-4','!use:care','m:water:0:0','!turn:water','m:lift:0:0','!valve:lift','f:0:4','!repair'],
 '3-4':['f:1:-4','!grow:root:right','!grow:root:right','!grow:root:right','!take:mirror','m:lift:0:0','!switch','m:water:0:0','!valve:water','!switch','!valve:lift','f:8:0','!drop:mirror:f:8:0','m:light:0:0','!turn:light','m:lift:0:0','!valve:lift','m:inner:0:0','!turn:inner','f:-4:0','!switch','f:-4:0','!switch','!repair'],
};
