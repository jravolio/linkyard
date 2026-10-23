"""Composes the README art (banner, hero, settings windows) from rendered UI and the brand icon.

usage: python3 -I compose.py <renders dir> <repo root>
Needs Google Chrome. Run render-ui.sh, which renders the views and then calls this.
"""
import base64
import pathlib
import subprocess
import sys

renders, root = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
assets = root / "docs/assets"
chrome = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"


def data(path):
    return "data:image/png;base64," + base64.b64encode(pathlib.Path(path).read_bytes()).decode()


ICON = data(root / "docs/brand/linkyard-icon-1024.png")
WALLPAPER = """background:
  radial-gradient(40% 55% at 15% 25%, #2d4f94 0, transparent 70%),
  radial-gradient(35% 50% at 85% 20%, #6b3d7d 0, transparent 72%),
  radial-gradient(45% 50% at 75% 95%, #1e6b66 0, transparent 70%),
  radial-gradient(35% 40% at 20% 100%, #8a5a2b 0, transparent 70%), #0b0e16;"""
BASE = """*{box-sizing:border-box;margin:0}
body{font-family:-apple-system,BlinkMacSystemFont,"SF Pro Display",sans-serif;-webkit-font-smoothing:antialiased;color:#f5f7ff}"""


def shoot(name, html, width, height):
    page = renders / f"{name.replace('/', '-')}.html"
    page.write_text(f"<!doctype html><meta charset=utf-8><style>{BASE}</style>{html}")
    subprocess.run([chrome, "--headless=new", "--hide-scrollbars", f"--user-data-dir={renders}/chrome",
                    "--force-device-scale-factor=2", f"--window-size={width},{height}",
                    f"--screenshot={assets / (name + '.png')}", page.as_uri()], check=True, capture_output=True)
    print(assets / f"{name}.png")


def window(title, image, width, crop_top=0, crop_height=None):
    view = f'<div style="height:{crop_height}px;overflow:hidden"><img src="{data(image)}" style="display:block;width:{width}px;margin-top:-{crop_top}px"></div>' if crop_height else f'<img src="{data(image)}" style="display:block;width:{width}px">'
    return f"""<div style="width:{width}px;border-radius:12px;overflow:hidden;background:#1e1e1e;
      box-shadow:0 0 0 .5px rgba(255,255,255,.18),0 30px 70px rgba(0,0,0,.55),0 8px 20px rgba(0,0,0,.35)">
      <div style="height:44px;display:flex;align-items:center;gap:8px;padding:0 16px;background:#2a2a2c;border-bottom:.5px solid rgba(0,0,0,.6)">
        <i style="width:12px;height:12px;border-radius:50%;background:#ff5f57"></i><i style="width:12px;height:12px;border-radius:50%;background:#febc2e"></i><i style="width:12px;height:12px;border-radius:50%;background:#28c840"></i>
        <span style="flex:1;text-align:center;margin-right:52px;font-size:13px;font-weight:600;color:rgba(255,255,255,.75)">{title}</span>
      </div>{view}</div>"""


shoot("linkyard-banner", f"""
<div style="width:1280px;height:400px;{WALLPAPER}display:flex;align-items:center;gap:44px;padding:0 96px;position:relative;overflow:hidden">
  <img src="{ICON}" style="width:230px;height:230px;filter:drop-shadow(0 18px 40px rgba(0,0,0,.45))">
  <div>
    <div style="font-size:96px;font-weight:800;letter-spacing:-3px;line-height:1">Linkyard</div>
    <div style="margin-top:16px;font-size:27px;font-weight:500;color:rgba(255,255,255,.82);max-width:760px;line-height:1.3">
      Every link to the right browser, as the right you.</div>
    <div style="margin-top:22px;font-size:16px;color:rgba(255,255,255,.55)">A tiny macOS link router · a community continuation of Browserino</div>
  </div>
</div>""", 1280, 400)

shoot("linkyard-hero", f"""
<div style="width:1200px;height:640px;{WALLPAPER}display:grid;place-items:center;position:relative">
  <div style="position:absolute;top:34px;left:50%;transform:translateX(-50%);display:flex;align-items:center;gap:10px;padding:9px 16px;border-radius:999px;
    background:rgba(20,22,30,.6);box-shadow:inset 0 0 0 .5px rgba(255,255,255,.2);font-size:15px;color:rgba(255,255,255,.85)">
    🔗 <b style="font-weight:600">github.com/acme/website/pull/42</b><span style="color:rgba(255,255,255,.5)">clicked in Slack</span></div>
  <img src="{data(renders / 'picker.png')}" style="width:{412 * 1.35:.0f}px;border-radius:18px;
    box-shadow:0 0 0 .5px rgba(255,255,255,.22),0 40px 90px rgba(0,0,0,.6),0 10px 24px rgba(0,0,0,.4)">
</div>""", 1200, 640)

shoot("screenshots/settings-profiles", f"""<div style="padding:40px;{WALLPAPER}">{window("Linkyard Settings — Profiles", renders / "settings-profiles.png", 760, 388, 640)}</div>""", 840, 764)
shoot("screenshots/settings-rules", f"""<div style="padding:40px;{WALLPAPER}">{window("Linkyard Settings — Rules", renders / "settings-rules.png", 760)}</div>""", 840, 474)
