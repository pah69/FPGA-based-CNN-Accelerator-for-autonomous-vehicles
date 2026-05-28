# 2026-05-22T23:57:24.138553424
import vitis

client = vitis.create_client()
client.set_workspace(path="sw_demo_zyboz7")

comp = client.create_app_component(name="app_component",platform = "$COMPONENT_LOCATION/../platform/export/platform/platform.xpfm",domain = "standalone_ps7_cortexa9_0")

platform = client.get_component(name="platform")
status = platform.build()

comp = client.get_component(name="app_component")
comp.build()

status = platform.build()

comp.build()

vitis.dispose()

