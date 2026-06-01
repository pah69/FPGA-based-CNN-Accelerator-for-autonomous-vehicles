# 2026-06-01T08:54:18.375026384
import vitis

client = vitis.create_client()
client.set_workspace(path="sw_demo_zcu104")

platform = client.get_component(name="tpu_platform")
status = platform.update_hw(hw_design = "$COMPONENT_LOCATION/../../synth/tpu_mnist_zcu104/tpu_mnist_zcu104.xsa")

status = platform.build()

status = platform.build()

comp = client.get_component(name="tpu_app")
comp.build()

status = platform.build()

comp.build()

vitis.dispose()

