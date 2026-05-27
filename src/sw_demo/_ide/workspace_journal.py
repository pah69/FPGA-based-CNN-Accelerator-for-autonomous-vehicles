# 2026-05-27T15:48:39.720869001
import vitis

client = vitis.create_client()
client.set_workspace(path="sw_demo")

platform = client.get_component(name="platform")
status = platform.build()

comp = client.get_component(name="tpu_app")
comp.build()

