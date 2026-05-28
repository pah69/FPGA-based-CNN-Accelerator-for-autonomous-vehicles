# 2026-05-28T08:34:44.400444033
import vitis

client = vitis.create_client()
client.set_workspace(path="sw_demo")

platform = client.get_component(name="platform")
status = platform.build()

comp = client.get_component(name="tpu_app")
comp.build()

status = platform.build()

comp.build()

vitis.dispose()

