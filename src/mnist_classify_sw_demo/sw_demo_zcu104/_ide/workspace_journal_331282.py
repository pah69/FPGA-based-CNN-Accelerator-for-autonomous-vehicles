# 2026-05-22T14:51:35.983598877
import vitis

client = vitis.create_client()
client.set_workspace(path="sw_demo")

platform = client.create_platform_component(name = "platform",hw_design = "$COMPONENT_LOCATION/../../synth/tpu_mnist/tpu_mnist.xsa",os = "standalone",cpu = "psu_cortexa53_0",domain_name = "standalone_psu_cortexa53_0",architecture = "64-bit",compiler = "gcc")

platform = client.get_component(name="platform")
status = platform.build()

comp = client.create_app_component(name="tpu_app",platform = "$COMPONENT_LOCATION/../platform/export/platform/platform.xpfm",domain = "standalone_psu_cortexa53_0")

status = platform.build()

comp = client.get_component(name="tpu_app")
comp.build()

status = platform.build()

comp.build()

vitis.dispose()

