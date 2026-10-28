This little script switches a GPU between the VFIO-PCI and the native graphics driver(AMDGPU, nouveau, i915, xe), so you can jump back and forth between giving a KVM guest exclusive use of the GPU and rendering your host Desktop, without restarting the system (just the graphical environment).

Add the pci addresses of the GPU and the associated audio device, along with the usual desktop driver in the info.txt, one per line, with the next format 
```
xx:xx.x graphics_driver 
xx:xx.x audio_driver  
``` 
if you don't know those you can find them with lscpi -k, this is an example of how it looks on my system: 
```
... 
09:00.0 VGA compatible controller: Advanced Micro Devices, Inc. [AMD/ATI] Navi 23 [Radeon RX 6600/6600 XT/6600M] (rev c7) 
Subsystem: Tul Corporation / PowerColor Device 2413 
Kernel driver in use: amdgpu 
Kernel modules: amdgpu 
09:00.1 Audio device: Advanced Micro Devices, Inc. [AMD/ATI] Navi 21/23 HDMI/DP Audio Controller Subsystem: Advanced Micro Devices, Inc. [AMD/ATI] Navi 21/23 HDMI/DP Audio Controller 
Kernel driver in use: snd_hda_intel 
Kernel modules: snd_hda_intel 
... 
```
so info.txt would look like:
```
 09:00.0 amdgpu
 09:00.1 snd_hda_intel
```

Remember to activate IOMMU on your EFI configuration.


