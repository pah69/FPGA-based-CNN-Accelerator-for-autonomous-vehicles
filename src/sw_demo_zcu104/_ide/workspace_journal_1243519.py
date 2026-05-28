# 2026-05-28T14:18:09.693149990
import vitis

client = vitis.create_client()
client.set_workspace(path="sw_demo")

platform = client.get_component(name="platform")
status = platform.build()

comp = client.get_component(name="tpu_app")
comp.build()

