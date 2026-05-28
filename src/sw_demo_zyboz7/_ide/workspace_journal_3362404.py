# 2026-05-22T23:53:51.672014451
import vitis

client = vitis.create_client()
client.set_workspace(path="sw_demo_zyboz7")

platform = client.create_platform_component(name = "platform",hw_design = "$COMPONENT_LOCATION/../../synth/tpu_mnist_zyboz7/tpu_zyboz7.xsa",os = "standalone",cpu = "ps7_cortexa9_0",domain_name = "standalone_ps7_cortexa9_0",compiler = "gcc")

platform = client.get_component(name="platform")
status = platform.build()

