# 2026-05-28T16:27:03.710893904
import vitis

client = vitis.create_client()
client.set_workspace(path="sw_demo_zcu104")

platform = client.create_platform_component(name = "tpu_platform",hw_design = "$COMPONENT_LOCATION/../../synth/tpu_mnist_zcu104/tpu_mnist_zcu104.xsa",os = "standalone",cpu = "psu_cortexa53_0",domain_name = "standalone_psu_cortexa53_0",architecture = "64-bit",compiler = "gcc")

platform = client.get_component(name="tpu_platform")
status = platform.build()

comp = client.get_component(name="tpu_app")
comp.build()

