# 2026-05-28T13:03:57.120800611
import vitis

client = vitis.create_client()
client.set_workspace(path="sw_demo")

comp = client.get_component(name="tpu_app")
status = comp.clean()

platform = client.get_component(name="platform")
status = platform.build()

comp.build()

vitis.dispose()

