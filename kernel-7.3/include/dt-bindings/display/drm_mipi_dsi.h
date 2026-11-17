/* SPDX-License-Identifier: GPL-2.0 */
/*
 * MIPI DSI bus flags and pixel formats for use in device tree.
 *
 * Values must stay in sync with the kernel-side definitions in
 * <drm/drm_mipi_dsi.h>.
 */

#ifndef __DT_BINDINGS_DRM_MIPI_DSI_H__
#define __DT_BINDINGS_DRM_MIPI_DSI_H__

/* DSI mode flags */
#define MIPI_DSI_MODE_VIDEO		(1 << 0)
#define MIPI_DSI_MODE_VIDEO_BURST	(1 << 1)
#define MIPI_DSI_MODE_VIDEO_SYNC_PULSE	(1 << 2)
#define MIPI_DSI_MODE_VIDEO_AUTO_VERT	(1 << 3)
#define MIPI_DSI_MODE_VIDEO_HSE		(1 << 4)
#define MIPI_DSI_MODE_VIDEO_NO_HFP	(1 << 5)
#define MIPI_DSI_MODE_VIDEO_NO_HBP	(1 << 6)
#define MIPI_DSI_MODE_VIDEO_NO_HSA	(1 << 7)
#define MIPI_DSI_MODE_NO_EOT_PACKET	(1 << 9)
#define MIPI_DSI_CLOCK_NON_CONTINUOUS	(1 << 10)
#define MIPI_DSI_MODE_LPM		(1 << 11)

/* DSI pixel formats */
#define MIPI_DSI_FMT_RGB888		0
#define MIPI_DSI_FMT_RGB666		1
#define MIPI_DSI_FMT_RGB666_PACKED	2
#define MIPI_DSI_FMT_RGB565		3
#define MIPI_DSI_FMT_RGB101010		4
#define MIPI_DSI_FMT_RGB121212		5

#endif /* __DT_BINDINGS_DRM_MIPI_DSI_H__ */
