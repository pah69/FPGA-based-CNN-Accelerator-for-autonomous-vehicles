# 2026-05-28T10:19:51.677808351
import vitis

client = vitis.create_client()
client.set_workspace(path="sw_demo")

platform = client.get_component(name="platform")
status = platform.update_hw(hw_design = "$COMPONENT_LOCATION/../../synth/tpu_mnist_zcu104/tpu_mnist_zcu104.xsa")

status = platform.build()

status = platform.build()

comp = client.get_component(name="tpu_app")
comp.build()

vitis.dispose()

