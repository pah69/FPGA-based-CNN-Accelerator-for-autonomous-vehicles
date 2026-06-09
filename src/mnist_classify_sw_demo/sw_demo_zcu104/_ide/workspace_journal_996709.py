# 2026-05-29T10:48:47.032745686
import vitis

client = vitis.create_client()
client.set_workspace(path="sw_demo_zcu104")

platform = client.get_component(name="tpu_platform")
status = platform.build()

comp = client.get_component(name="tpu_app")
comp.build()

status = comp.clean()

status = platform.build()

comp.build()

vitis.dispose()

