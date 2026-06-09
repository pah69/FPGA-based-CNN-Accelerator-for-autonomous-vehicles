# 2026-05-26T13:00:12.450954868
import vitis

client = vitis.create_client()
client.set_workspace(path="sw_demo_zyboz7")

client.delete_component(name="platform")

platform = client.create_platform_component(name = "platform",hw_design = "$COMPONENT_LOCATION/../../synth/tpu_mnist_zyboz7/tpu_zyboz7.xsa",os = "standalone",cpu = "ps7_cortexa9_0",domain_name = "standalone_ps7_cortexa9_0",compiler = "gcc")

client.delete_component(name="hello_world")

client.delete_component(name="componentName")

platform = client.get_component(name="platform")
status = platform.update_hw(hw_design = "$COMPONENT_LOCATION/../../synth/tpu_mnist_zyboz7/tpu_zyboz7.xsa")

status = platform.build()

status = platform.build()

comp = client.get_component(name="app_component")
comp.build()

vitis.dispose()

