# 2026-05-28T15:16:16.939157554
import vitis

client = vitis.create_client()
client.set_workspace(path="sw_demo_zcu104")

platform = client.get_component(name="platform")
status = platform.build()

comp = client.get_component(name="tpu_app")
status = comp.clean()

status = platform.update_hw(hw_design = "$COMPONENT_LOCATION/../../synth/tpu_mnist_zcu104/tpu_mnist_zcu104.xsa")

status = platform.build()

status = platform.build()

comp.build()

status = platform.build()

comp.build()

client.delete_component(name="platform")

vitis.dispose()

