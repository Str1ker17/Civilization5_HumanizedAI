#!/bin/sh
f=${SNAP_USER_COMMON:-$HOME/snap/steam/common}/civ5-autoplay.env
if [ -f "$f" ] && [ $(($(date +%s) - $(stat -c %Y "$f"))) -lt 120 ]; then
	while IFS='=' read -r key value; do
		case $key in
		DISPLAY | PROTON_USE_WINED3D | PROTON_LOG | VK_ICD_FILENAMES | LIBGL_ALWAYS_SOFTWARE | DXVK_HUD | DXVK_CONFIG | MESA_VK_WSI_DEBUG | LP_NUM_THREADS)
			export "$key=$value"
			;;
		esac
	done < "$f"
	unset WAYLAND_DISPLAY
fi
exec "$@"
