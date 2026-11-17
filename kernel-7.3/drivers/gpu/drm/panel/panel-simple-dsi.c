// SPDX-License-Identifier: GPL-2.0-only
/*
 * Generic MIPI-DSI panel driver configured entirely from device tree.
 *
 * This driver is compatible with the Rockchip vendor kernel "simple-panel-dsi"
 * binding, so existing device tree panel nodes (panel-init-sequence,
 * panel-exit-sequence, display-timings, dsi,lanes/format/flags and the
 * *-delay-ms properties) can be reused without modification.
 */

#include <linux/delay.h>
#include <linux/gpio/consumer.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/regulator/consumer.h>

#include <drm/drm_mipi_dsi.h>
#include <drm/drm_modes.h>
#include <drm/drm_panel.h>
#include <drm/drm_probe_helper.h>

#include <video/mipi_display.h>
#include <video/of_display_timing.h>
#include <video/of_videomode.h>
#include <video/videomode.h>

struct panel_simple_dsi_cmd {
	u8 data_type;
	u8 delay;
	u8 payload_length;
	const u8 *payload;
};

struct panel_simple_dsi_cmd_seq {
	struct panel_simple_dsi_cmd *cmds;
	unsigned int cmd_cnt;
};

struct panel_simple_dsi {
	struct drm_panel panel;
	struct mipi_dsi_device *dsi;
	struct regulator *power;
	struct gpio_desc *reset_gpio;
	struct gpio_desc *enable_gpio;
	struct videomode vm;
	struct drm_display_mode mode;
	unsigned int prepare_delay;
	unsigned int enable_delay;
	unsigned int disable_delay;
	unsigned int unprepare_delay;
	unsigned int reset_delay;
	unsigned int init_delay;
	struct panel_simple_dsi_cmd_seq init_seq;
	struct panel_simple_dsi_cmd_seq exit_seq;
};

static inline struct panel_simple_dsi *
to_panel_simple_dsi(struct drm_panel *panel)
{
	return container_of(panel, struct panel_simple_dsi, panel);
}

static void panel_simple_dsi_sleep(unsigned int msecs)
{
	if (msecs)
		msleep(msecs);
}

static int panel_simple_dsi_parse_cmd_seq(struct device *dev,
					  const u8 *data, int length,
					  struct panel_simple_dsi_cmd_seq *seq)
{
	struct panel_simple_dsi_cmd *cmd;
	u8 *buf, *d;
	int i, cnt, len;

	buf = devm_kmemdup(dev, data, length, GFP_KERNEL);
	if (!buf)
		return -ENOMEM;

	/* Each entry is: data_type(1) delay(1) payload_length(1) payload... */
	d = buf;
	len = length;
	cnt = 0;
	while (len >= 3) {
		u8 payload_length = d[2];

		if (payload_length > len - 3)
			return -EINVAL;

		d += 3 + payload_length;
		len -= 3 + payload_length;
		cnt++;
	}

	if (len)
		return -EINVAL;

	seq->cmd_cnt = cnt;
	seq->cmds = devm_kcalloc(dev, cnt, sizeof(*seq->cmds), GFP_KERNEL);
	if (!seq->cmds)
		return -ENOMEM;

	d = buf;
	len = length;
	for (i = 0; i < cnt; i++) {
		cmd = &seq->cmds[i];
		cmd->data_type = d[0];
		cmd->delay = d[1];
		cmd->payload_length = d[2];
		cmd->payload = d + 3;

		d += 3 + cmd->payload_length;
		len -= 3 + cmd->payload_length;
	}

	return 0;
}

static int panel_simple_dsi_xfer_cmd_seq(struct panel_simple_dsi *ctx,
					 struct panel_simple_dsi_cmd_seq *seq)
{
	struct mipi_dsi_device *dsi = ctx->dsi;
	int i, ret;

	for (i = 0; i < seq->cmd_cnt; i++) {
		struct panel_simple_dsi_cmd *cmd = &seq->cmds[i];

		switch (cmd->data_type) {
		case MIPI_DSI_GENERIC_SHORT_WRITE_0_PARAM:
		case MIPI_DSI_GENERIC_SHORT_WRITE_1_PARAM:
		case MIPI_DSI_GENERIC_SHORT_WRITE_2_PARAM:
		case MIPI_DSI_GENERIC_LONG_WRITE:
			ret = mipi_dsi_generic_write(dsi, cmd->payload,
						     cmd->payload_length);
			break;
		case MIPI_DSI_DCS_SHORT_WRITE:
		case MIPI_DSI_DCS_SHORT_WRITE_PARAM:
		case MIPI_DSI_DCS_LONG_WRITE:
			ret = mipi_dsi_dcs_write_buffer(dsi, cmd->payload,
							cmd->payload_length);
			break;
		default:
			dev_err(&dsi->dev, "unsupported DSI data type 0x%02x\n",
				cmd->data_type);
			return -EINVAL;
		}

		if (ret < 0) {
			dev_err(&dsi->dev, "failed to send DSI command: %d\n",
				ret);
			return ret;
		}

		panel_simple_dsi_sleep(cmd->delay);
	}

	return 0;
}

static int panel_simple_dsi_prepare(struct drm_panel *panel)
{
	struct panel_simple_dsi *ctx = to_panel_simple_dsi(panel);
	int ret;

	if (ctx->power) {
		ret = regulator_enable(ctx->power);
		if (ret < 0)
			return ret;
	}

	if (ctx->enable_gpio)
		gpiod_set_value_cansleep(ctx->enable_gpio, 1);

	panel_simple_dsi_sleep(ctx->prepare_delay);

	if (ctx->reset_gpio) {
		gpiod_set_value_cansleep(ctx->reset_gpio, 1);
		panel_simple_dsi_sleep(ctx->reset_delay);
		gpiod_set_value_cansleep(ctx->reset_gpio, 0);
		panel_simple_dsi_sleep(ctx->init_delay);
	}

	ret = panel_simple_dsi_xfer_cmd_seq(ctx, &ctx->init_seq);
	if (ret < 0) {
		if (ctx->power)
			regulator_disable(ctx->power);
		return ret;
	}

	return 0;
}

static int panel_simple_dsi_enable(struct drm_panel *panel)
{
	struct panel_simple_dsi *ctx = to_panel_simple_dsi(panel);

	panel_simple_dsi_sleep(ctx->enable_delay);

	return 0;
}

static int panel_simple_dsi_disable(struct drm_panel *panel)
{
	struct panel_simple_dsi *ctx = to_panel_simple_dsi(panel);

	panel_simple_dsi_sleep(ctx->disable_delay);

	return 0;
}

static int panel_simple_dsi_unprepare(struct drm_panel *panel)
{
	struct panel_simple_dsi *ctx = to_panel_simple_dsi(panel);

	if (panel_simple_dsi_xfer_cmd_seq(ctx, &ctx->exit_seq))
		dev_warn(panel->dev, "failed to send panel exit sequence\n");

	if (ctx->reset_gpio)
		gpiod_set_value_cansleep(ctx->reset_gpio, 1);
	if (ctx->enable_gpio)
		gpiod_set_value_cansleep(ctx->enable_gpio, 0);
	if (ctx->power)
		regulator_disable(ctx->power);

	panel_simple_dsi_sleep(ctx->unprepare_delay);

	return 0;
}

static int panel_simple_dsi_get_modes(struct drm_panel *panel,
				      struct drm_connector *connector)
{
	struct panel_simple_dsi *ctx = to_panel_simple_dsi(panel);
	struct drm_display_mode *mode;

	mode = drm_mode_duplicate(connector->dev, &ctx->mode);
	if (!mode)
		return -ENOMEM;

	mode->type |= DRM_MODE_TYPE_DRIVER | DRM_MODE_TYPE_PREFERRED;
	drm_mode_set_name(mode);
	drm_mode_probed_add(connector, mode);

	return 1;
}

static const struct drm_panel_funcs panel_simple_dsi_panel_funcs = {
	.prepare = panel_simple_dsi_prepare,
	.enable = panel_simple_dsi_enable,
	.disable = panel_simple_dsi_disable,
	.unprepare = panel_simple_dsi_unprepare,
	.get_modes = panel_simple_dsi_get_modes,
};

static int panel_simple_dsi_probe(struct mipi_dsi_device *dsi)
{
	struct device *dev = &dsi->dev;
	struct panel_simple_dsi *ctx;
	const u8 *data;
	int len, ret;
	u32 val;

	ctx = devm_drm_panel_alloc(dev, __typeof__(*ctx), panel,
				   &panel_simple_dsi_panel_funcs,
				   DRM_MODE_CONNECTOR_DSI);
	if (IS_ERR(ctx))
		return PTR_ERR(ctx);

	ctx->dsi = dsi;
	mipi_dsi_set_drvdata(dsi, ctx);

	ret = of_get_videomode(dev->of_node, &ctx->vm, OF_USE_NATIVE_MODE);
	if (ret) {
		dev_err(dev, "failed to get display timings: %d\n", ret);
		return ret;
	}

	drm_display_mode_from_videomode(&ctx->vm, &ctx->mode);
	of_property_read_u32(dev->of_node, "size,width", &val);
	ctx->mode.width_mm = val;
	of_property_read_u32(dev->of_node, "size,height", &val);
	ctx->mode.height_mm = val;

	of_property_read_u32(dev->of_node, "prepare-delay-ms",
			     &ctx->prepare_delay);
	of_property_read_u32(dev->of_node, "enable-delay-ms",
			     &ctx->enable_delay);
	of_property_read_u32(dev->of_node, "disable-delay-ms",
			     &ctx->disable_delay);
	of_property_read_u32(dev->of_node, "unprepare-delay-ms",
			     &ctx->unprepare_delay);
	of_property_read_u32(dev->of_node, "reset-delay-ms",
			     &ctx->reset_delay);
	of_property_read_u32(dev->of_node, "init-delay-ms", &ctx->init_delay);

	data = of_get_property(dev->of_node, "panel-init-sequence", &len);
	if (data) {
		ret = panel_simple_dsi_parse_cmd_seq(dev, data, len,
						     &ctx->init_seq);
		if (ret)
			return ret;
	}

	data = of_get_property(dev->of_node, "panel-exit-sequence", &len);
	if (data) {
		ret = panel_simple_dsi_parse_cmd_seq(dev, data, len,
						     &ctx->exit_seq);
		if (ret)
			return ret;
	}

	ctx->power = devm_regulator_get_optional(dev, "power");
	if (IS_ERR(ctx->power)) {
		if (PTR_ERR(ctx->power) == -ENODEV)
			ctx->power = NULL;
		else
			return dev_err_probe(dev, PTR_ERR(ctx->power),
					     "Failed to get power-supply\n");
	}

	ctx->reset_gpio = devm_gpiod_get_optional(dev, "reset", GPIOD_OUT_LOW);
	if (IS_ERR(ctx->reset_gpio))
		return dev_err_probe(dev, PTR_ERR(ctx->reset_gpio),
				     "Failed to get reset-gpios\n");

	ctx->enable_gpio = devm_gpiod_get_optional(dev, "enable", GPIOD_OUT_LOW);
	if (IS_ERR(ctx->enable_gpio))
		return dev_err_probe(dev, PTR_ERR(ctx->enable_gpio),
				     "Failed to get enable-gpios\n");

	dsi->mode_flags = MIPI_DSI_MODE_VIDEO | MIPI_DSI_MODE_VIDEO_BURST;
	dsi->format = MIPI_DSI_FMT_RGB888;
	dsi->lanes = 1;

	if (!of_property_read_u32(dev->of_node, "dsi,flags", &val))
		dsi->mode_flags = val;
	if (!of_property_read_u32(dev->of_node, "dsi,format", &val))
		dsi->format = val;
	if (!of_property_read_u32(dev->of_node, "dsi,lanes", &val))
		dsi->lanes = val;

	ctx->panel.prepare_prev_first = true;

	ret = drm_panel_of_backlight(&ctx->panel);
	if (ret == -EPROBE_DEFER)
		return ret;
	if (ret)
		dev_warn(dev, "failed to get backlight: %d\n", ret);

	drm_panel_add(&ctx->panel);

	ret = mipi_dsi_attach(dsi);
	if (ret < 0) {
		dev_err_probe(dev, ret, "Failed to attach to DSI host\n");
		drm_panel_remove(&ctx->panel);
		return ret;
	}

	return 0;
}

static void panel_simple_dsi_remove(struct mipi_dsi_device *dsi)
{
	struct panel_simple_dsi *ctx = mipi_dsi_get_drvdata(dsi);
	int ret;

	ret = mipi_dsi_detach(dsi);
	if (ret < 0)
		dev_err(&dsi->dev, "Failed to detach from DSI host: %d\n", ret);

	drm_panel_remove(&ctx->panel);
}

static const struct of_device_id panel_simple_dsi_of_match[] = {
	{ .compatible = "simple-panel-dsi" },
	{ /* sentinel */ }
};
MODULE_DEVICE_TABLE(of, panel_simple_dsi_of_match);

static struct mipi_dsi_driver panel_simple_dsi_driver = {
	.probe = panel_simple_dsi_probe,
	.remove = panel_simple_dsi_remove,
	.driver = {
		.name = "panel-simple-dsi",
		.of_match_table = panel_simple_dsi_of_match,
	},
};
module_mipi_dsi_driver(panel_simple_dsi_driver);

MODULE_DESCRIPTION("Device tree configured generic MIPI-DSI panel driver");
MODULE_LICENSE("GPL");
