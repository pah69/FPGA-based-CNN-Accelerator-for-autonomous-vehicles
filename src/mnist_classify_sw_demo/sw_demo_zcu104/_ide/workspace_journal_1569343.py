# 2026-05-28T14:42:23.067282819
import vitis

client = vitis.create_client()
client.set_workspace(path="sw_demo_zcu104")

platform = client.get_component(name="platform")
status = platform.build()

status = platform.build()

comp = client.get_component(name="tpu_app")
comp.build()

status = platform.build()

comp.build()

status = platform.build()

comp.build()

vitis.dispose()

