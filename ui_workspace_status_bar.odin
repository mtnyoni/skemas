package main

import "core:fmt"
import "core:math"
import "core:strings"
import im "vendor/odin-imgui"

StatusBar_Props :: struct {
	y_pos:            f32,
	display_w:        f32,
	query_time_ms:    f32,
	state:            ^App_State,
	pg_major_version: i32,
	conn_status:      ConnectionStatus,
}

StatusBar :: proc(props: ^StatusBar_Props) {
	im.SetNextWindowPos({0, props.y_pos}, .Always)
	im.SetNextWindowSize({props.display_w, WORKSPACE_STATUS_BAR_H}, .Always)
	im.PushStyleVar(.WindowBorderSize, 0.0)
	im.PushStyleVarY(.WindowPadding, 0.0)
	// im.PushStyleColorImVec4(.WindowBg, im.Vec4{0.15, 0.35, 0.70, 1.0})

	defer im.PopStyleVar(2)

	im.Begin(
		"##statusbar",
		nil,
		{.NoMove, .NoResize, .NoCollapse, .NoTitleBar, .NoScrollbar, .NoScrollWithMouse},
	)
	defer im.End()

	im.PushFont(FONT_REGULAR_SM)
	defer im.PopFont()

	center_y := (WORKSPACE_STATUS_BAR_H - im.GetTextLineHeight()) / 2
	im.SetCursorPosY(center_y)
	connection_status_text(props.conn_status, props.pg_major_version, props.state)

	style := im.GetStyle()
	latency_str :=
		fmt.tprintf("%.0f µs", props.state.latency * 1000) if props.state.latency < 1.0 else fmt.tprintf("%.1f ms", props.state.latency)
	latency_lbl := strings.clone_to_cstring(latency_str, context.temp_allocator)
	latency_w := im.CalcTextSize(latency_lbl).x
	im.SameLine(WORKSPACE_SIDEBAR_WIDTH - latency_w - style.WindowPadding.x)
	im.SetCursorPosY(center_y)
	im.TextDisabled(latency_lbl)

	draw_list := im.GetWindowDrawList()
	x := WORKSPACE_SIDEBAR_WIDTH
	p0 := im.Vec2{im.GetWindowPos().x + x, im.GetWindowPos().y}
	p1 := im.Vec2{im.GetWindowPos().x + x, im.GetWindowPos().y + WORKSPACE_STATUS_BAR_H}
	im.DrawList_AddLine(draw_list, p0, p1, im.GetColorU32(.Separator), 1.0)

	im.PushStyleColor(.Separator, im.GetColorU32(.Separator))
	defer im.PopStyleColor()

	im.SameLine(WORKSPACE_SIDEBAR_WIDTH + style.WindowPadding.x)
	im.SetCursorPosY(center_y)
	number_of_rows_text(103, 1000)

	im.SameLine()
	im.SetCursorPosY(center_y)
	im.SeparatorEx({.Vertical})

	im.SameLine()
	im.SetCursorPosY(center_y)
	im.PushFont(FONT_MEDIUM_SM)
	im.Text("1")
	im.PopFont()
	im.SameLine(0, 3)
	im.TextDisabled("Selected")

	if props.query_time_ms > 0 {
		im.SameLine()
		im.SetCursorPosY(center_y)
		im.SeparatorEx({.Vertical})

		s := strings.clone_to_cstring(
			fmt.tprintf("%.0fms", props.query_time_ms),
			context.temp_allocator,
		)
		im.SameLine()
		im.SetCursorPosY(center_y)
		im.TextDisabled("Query")
		im.SameLine()
		im.PushFont(FONT_MEDIUM_SM)
		im.Text(s)
		im.PopFont()
	}

	// Right-aligned section, rendered left-to-right: [<1-14>] | [UTF8] | [Read-only Off]
	readonly_lbl: cstring = "Read-only Off"
	encoding_type_lbl: cstring = "UTF8"
	pages_lbl: cstring = "<1-14>"

	readonly_w := im.CalcTextSize(readonly_lbl).x
	encoding_type_w := im.CalcTextSize(encoding_type_lbl).x
	pages_w := im.CalcTextSize(pages_lbl).x
	sep_w: f32 = 1.0 + style.ItemSpacing.x * 2

	right_total_w := pages_w + sep_w + encoding_type_w + sep_w + readonly_w
	right_start := props.display_w - style.WindowPadding.x - right_total_w

	im.SameLine(right_start)
	im.SetCursorPosY(center_y)
	im.TextDisabled(pages_lbl)

	im.SameLine()
	im.SetCursorPosY(center_y)
	im.SeparatorEx({.Vertical})

	im.SameLine()
	im.SetCursorPosY(center_y)
	im.TextDisabled(encoding_type_lbl)

	im.SameLine()
	im.SetCursorPosY(center_y)
	im.SeparatorEx({.Vertical})

	im.SameLine()
	im.SetCursorPosY(center_y)
	im.TextDisabled(readonly_lbl)
}

connection_status_text :: proc(
	conn_status: ConnectionStatus,
	pg_major_version: i32,
	state: ^App_State,
) {
	draw_list := im.GetWindowDrawList()
	pos := im.GetCursorScreenPos()

	draw_status_indicator(3, COLOR_GREEN_ACCENT_LIGHT, COLOR_GREEN_ACCENT, pos, draw_list)
	im.SameLine(0, 3)
	status_labels := [ConnectionStatus]string {
		.Connected    = "Connected",
		.Disconnected = "Disconnected",
		.Connecting   = "Connecting",
	}
	status_lbl := status_labels[conn_status]
	im.TextDisabled(strings.clone_to_cstring(status_lbl), context.temp_allocator)
	status_label_w :=
		im.CalcTextSize(strings.clone_to_cstring(status_lbl, context.temp_allocator)).x

	im.SameLine(0, 2)
	dot_pos := im.GetCursorScreenPos()
	im.DrawList_AddCircleFilled(
		draw_list,
		{dot_pos.x + 1.5, dot_pos.y + im.GetTextLineHeight() / 2},
		1.5,
		im.GetColorU32(.Separator),
	)

	im.Dummy({3, 0})
	im.SameLine(0, 3)
	switch conn in state.conn {
	case PQ_Conn:
		label := strings.clone_to_cstring(
			fmt.tprintf("Postgres %d", pg_major_version),
			context.temp_allocator,
		)
		im.Text(label)

	case SQLite_Conn:
		im.Text("SQLite")
	}
}

number_of_rows_text :: proc(count: int, total_rows: int) {
	im.PushFont(FONT_MEDIUM_SM)
	im.Text(strings.clone_to_cstring(fmt.tprintf("%d", count), context.temp_allocator))
	im.PopFont()
	im.SameLine(0, 3)
	im.TextDisabled("of")
	im.SameLine(0, 3)
	im.PushFont(FONT_MEDIUM_SM)
	im.Text(strings.clone_to_cstring(fmt.tprintf("%d", total_rows), context.temp_allocator))
	im.PopFont()
	im.SameLine(0, 3)
	im.TextDisabled("rows")
}

draw_status_indicator :: proc(
	radius: f32,
	outer_color, inner_color: im.Vec4,
	pos: im.Vec2,
	draw_list: ^im.DrawList,
) {
	size := im.Vec2{radius * 2, radius * 2}
	center := im.Vec2{pos.x + radius, pos.y + im.GetTextLineHeight() / 2}

	im.Dummy(size)

	time := f32(im.GetTime())
	ping_duration: f32 = 0.7 // seconds.

	ping_factor := math.mod(time, ping_duration) / ping_duration
	outer_ping_radius := radius + (radius * 0.7 * ping_factor)
	animated_outer_color := outer_color
	animated_outer_color.w *= (1.0 - ping_factor)

	im.DrawList_AddCircleFilled(
		draw_list,
		center,
		outer_ping_radius,
		im.GetColorU32ImVec4(animated_outer_color),
		0,
	)

	im.DrawList_AddCircleFilled(draw_list, center, radius, im.GetColorU32ImVec4(outer_color), 0)
	im.SameLine()
	im.DrawList_AddCircleFilled(
		draw_list,
		center,
		radius * 0.4,
		im.GetColorU32ImVec4(inner_color),
		0,
	)
}
