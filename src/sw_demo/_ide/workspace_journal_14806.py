# 2026-05-26T08:31:01.252586698
import vitis

client = vitis.create_client()
client.set_workspace(path="sw_demo")

platform = client.get_component(name="platform")
status = platform.build()

comp = client.get_component(name="tpu_app")
comp.build()

status = platform.build()

comp.build()

status = platform.build()

comp.build()

status = comp.clean()

status = platform.build()

comp.build()

status = platform.build()

comp.build()

status = comp.clean()

status = platform.build()

comp.build()

status = platform.build()

comp.build()

status = platform.build()

comp.build()

status = platform.build()

comp.build()

