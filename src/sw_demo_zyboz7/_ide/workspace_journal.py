# 2026-05-26T13:25:32.652940280
import vitis

client = vitis.create_client()
client.set_workspace(path="sw_demo_zyboz7")

platform = client.create_platform_component(name = "zybo_platform",hw_design = "$COMPONENT_LOCATION/../../synth/tpu_mnist_zyboz7/tpu_zybo.xsa",os = "standalone",cpu = "ps7_cortexa9_1",domain_name = "standalone_ps7_cortexa9_1",compiler = "gcc")

platform = client.get_component(name="zybo_platform")
status = platform.update_hw(hw_design = "$COMPONENT_LOCATION/../../synth/tpu_mnist_zyboz7/tpu_zybo.xsa")

status = platform.build()

comp = client.get_component(name="app_component")
status = comp.clean()

comp.build()

comp.build()

status = platform.update_hw(hw_design = "$COMPONENT_LOCATION/../../synth/tpu_mnist_zyboz7/tpu_zybo.xsa")

comp.build()

comp.build()

client.delete_component(name="app_component")

client.delete_component(name="componentName")

comp = client.create_app_component(name="app",platform = "$COMPONENT_LOCATION/../zybo_platform/export/zybo_platform/zybo_platform.xpfm",domain = "standalone_ps7_cortexa9_1")

status = platform.build()

comp = client.get_component(name="app")
comp.build()

vitis.dispose()

