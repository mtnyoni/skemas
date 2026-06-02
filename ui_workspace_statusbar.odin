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
	page_info:        PageInfo,
}

StatusBar :: proc(props: ^StatusBar_Props) {
	im.SetNextWindowPos({0, props.y_pos}, .Always)
	im.SetNextWindowSize({props.display_w, WORKSPACE_STATUS_BAR_H}, .Always)
	im.PushStyleVar(.WindowBorderSize, 0.0)
	im.PushStyleVarY(.WindowPadding, 0.0)
	defer im.PopStyleVar(2)

	im.Begin(
		"##statusbar",
		nil,
		{.NoMove, .NoResize, .NoCollapse, .NoTitleBar, .NoScrollbar, .NoScrollWithMouse, .NoDocking},
	)
	defer im.End()

	im.PushFontFloat(FONT_REGULAR, FONT_SIZE_XS)
	defer im.PopFont()

	draw_list := im.GetWindowDrawList()
	win_pos := im.GetWindowPos()
	im.DrawList_AddLine(
		draw_list,
		{win_pos.x, win_pos.y},
		{win_pos.x + props.display_w, win_pos.y},
		im.GetColorU32(.Separator),
		1.0,
	)

	center_y := (WORKSPACE_STATUS_BAR_H - FONT_SIZE_XS) / 2
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

	sep_color := im.GetColorU32(.Separator)
	vertical_separator :: proc(dl: ^im.DrawList, wp: im.Vec2, col: u32) {
		x := im.GetCursorScreenPos().x
		im.Dummy({1, 0})
		im.DrawList_AddLine(dl, {x, wp.y + 7}, {x, wp.y + WORKSPACE_STATUS_BAR_H - 7}, col, 1.0)
	}

	im.DrawList_AddLine(
		draw_list,
		{win_pos.x + WORKSPACE_SIDEBAR_WIDTH, win_pos.y},
		{win_pos.x + WORKSPACE_SIDEBAR_WIDTH, win_pos.y + WORKSPACE_STATUS_BAR_H},
		sep_color,
		1.0,
	)

	im.SameLine(WORKSPACE_SIDEBAR_WIDTH + style.WindowPadding.x)
	im.SetCursorPosY(center_y)
	number_of_rows_text(103, 1000)

	im.SameLine()
	vertical_separator(draw_list, win_pos, sep_color)

	im.SameLine()
	im.SetCursorPosY(center_y)
	im.PushFontFloat(FONT_MEDIUM, FONT_SIZE_XS)
	im.Text("1")
	im.PopFont()
	im.SameLine(0, 3)
	im.TextDisabled("Selected")

	if props.query_time_ms > 0 {
		im.SameLine()
		vertical_separator(draw_list, win_pos, sep_color)

		s := strings.clone_to_cstring(
			fmt.tprintf("%.0fms", props.query_time_ms),
			context.temp_allocator,
		)
		im.SameLine()
		im.SetCursorPosY(center_y)
		im.TextDisabled("Query")
		im.SameLine()
		im.PushFontFloat(FONT_MEDIUM, FONT_SIZE_XS)
		im.Text(s)
		im.PopFont()
	}

	readonly_lbl: cstring = "Read-only On" if props.state.read_only else "Read-only Off"
	encoding_type_lbl := strings.clone_to_cstring(
		props.state.encoding if props.state.encoding != "" else "UTF8",
		context.temp_allocator,
	)

	readonly_w := im.CalcTextSize(readonly_lbl).x
	encoding_type_w := im.CalcTextSize(encoding_type_lbl).x
	sep_w: f32 = 1.0 + style.ItemSpacing.x * 2

	cur_page_lbl := strings.clone_to_cstring(
		fmt.tprintf("%d", props.page_info.current_page^),
		context.temp_allocator,
	)
	total_pages_lbl := strings.clone_to_cstring(
		fmt.tprintf("%d", props.page_info.total_pages^),
		context.temp_allocator,
	)
	im.PushFontFloat(FONT_MEDIUM, FONT_SIZE_XS)
	cur_page_w := im.CalcTextSize(cur_page_lbl).x
	total_pages_w_val := im.CalcTextSize(total_pages_lbl).x
	im.PopFont()
	of_w := im.CalcTextSize("of").x
	NAV_ICON_SIZE :: f32(11.0)
	chevron_buf: [5]u8
	im.PushFontFloat(FONT_ICONS, NAV_ICON_SIZE)
	nav_icon_w := im.CalcTextSize(icon_str(.ChevronRight, &chevron_buf)).x
	im.PopFont()
	nav_btn_w := nav_icon_w + style.FramePadding.x * 2
	pages_w := nav_btn_w + 4 + cur_page_w + 3 + of_w + 3 + total_pages_w_val + 4 + nav_btn_w

	BELL_ICON_SIZE :: f32(15.0)

	bell_buf: [5]u8
	bell_lbl := icon_str(.Bell, &bell_buf)
	im.PushFontFloat(FONT_ICONS, BELL_ICON_SIZE)
	bell_w := im.CalcTextSize(bell_lbl).x
	im.PopFont()

	right_total_w := pages_w + sep_w + encoding_type_w + sep_w + readonly_w + sep_w + bell_w
	right_start := props.display_w - style.WindowPadding.x - right_total_w

	im.SameLine(right_start)
	im.SetCursorPosY(center_y)
	draw_pagination_ctrls(props.page_info)

	im.SameLine()
	vertical_separator(draw_list, win_pos, sep_color)

	im.SameLine()
	im.SetCursorPosY(center_y)
	im.TextDisabled(encoding_type_lbl)

	im.SameLine()
	vertical_separator(draw_list, win_pos, sep_color)

	im.SameLine()
	im.SetCursorPosY(center_y)
	im.TextDisabled(readonly_lbl)

	im.SameLine()
	vertical_separator(draw_list, win_pos, sep_color)

	im.SameLine()
	bell_pos := im.Vec2 {
		im.GetCursorScreenPos().x,
		win_pos.y + (WORKSPACE_STATUS_BAR_H - BELL_ICON_SIZE) * 0.5,
	}
	im.DrawList_AddTextImFontPtr(
		draw_list,
		FONT_ICONS,
		BELL_ICON_SIZE,
		bell_pos,
		im.GetColorU32ImVec4(COLOR_MUTED_FOREGROUND),
		bell_lbl,
	)
	im.Dummy({bell_w, 0})
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

	db_lbl: cstring
	switch conn in state.conn {
	case PQ_Conn:
		db_lbl = strings.clone_to_cstring(
			fmt.tprintf("Postgres %d", pg_major_version),
			context.temp_allocator,
		)
	case SQLite_Conn:
		db_lbl = strings.clone_to_cstring("SQLite", context.temp_allocator)
	}

	lbl_size := im.CalcTextSize(db_lbl)

	im.Text(db_lbl)

	if im.IsItemHovered() {
		im.SetMouseCursor(.Hand)

		if im.IsItemClicked(.Left) {
			im.OpenPopup("DbContextMenu")
		}
	}

	display_size := im.GetIO().DisplaySize
	target_y := display_size.y - WORKSPACE_STATUS_BAR_H - 2
	current_x := im.GetItemRectMin().x
	im.SetNextWindowPos({current_x, target_y}, .Appearing, {0.0, 1.0})

	im.PushStyleVarImVec2(.WindowPadding, {10, 8})
	im.PushStyleVar(.PopupRounding, 4)
	defer im.PopStyleVar(2)

	if im.BeginPopup("DbContextMenu") {
		defer im.EndPopup()

		im.PushStyleColorImVec4(.HeaderHovered, COLOR_MUTED_BACKGROUND)
		defer im.PopStyleColor()

		im.PushStyleVar(.FrameRounding, 4)
		defer im.PopStyleVar(1)

		if im.MenuItem("Refresh Database") {
			state.db_needs_reload = true
		}

		if im.MenuItem("Disconnect") {
			state.conn = nil
			state.conn_status = .Disconnected
			state.db_needs_reload = true
			state.screen = .ConnectionScreen
			im.CloseCurrentPopup()
		}
	}
}

number_of_rows_text :: proc(count: int, total_rows: int) {
	im.PushFontFloat(FONT_MEDIUM, FONT_SIZE_XS)
	im.Text(strings.clone_to_cstring(fmt.tprintf("%d", count), context.temp_allocator))
	im.PopFont()
	im.SameLine(0, 3)
	im.TextDisabled("of")
	im.SameLine(0, 3)
	im.PushFontFloat(FONT_MEDIUM, FONT_SIZE_XS)
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


PageInfo :: struct {
	current_page: ^int,
	total_pages:  ^int,
}

draw_pagination_ctrls :: proc(page_info: PageInfo) {
	NAV_ICON_SIZE :: f32(11.0)

	nav_btn :: proc(icon: Icon, id: cstring, enabled: bool) -> bool {
		style := im.GetStyle()
		dl := im.GetWindowDrawList()
		btn_h := im.GetTextLineHeight()

		icon_buf: [5]u8
		im.PushFontFloat(FONT_ICONS, NAV_ICON_SIZE)
		icon_w := im.CalcTextSize(icon_str(icon, &icon_buf)).x
		im.PopFont()
		btn_w := icon_w + style.FramePadding.x * 2

		pos := im.GetCursorScreenPos()
		im.PushID(id)
		im.InvisibleButton("##nav", {btn_w, btn_h})
		im.PopID()

		clicked := im.IsItemClicked() && enabled
		if im.IsItemHovered() && enabled {
			im.DrawList_AddRectFilled(
				dl,
				pos,
				{pos.x + btn_w, pos.y + btn_h},
				im.GetColorU32(.ButtonHovered),
				3,
			)
		}

		col := im.GetColorU32(.Text) if enabled else im.GetColorU32(.TextDisabled)
		icon_pos := im.Vec2{pos.x + style.FramePadding.x, pos.y + (btn_h - NAV_ICON_SIZE) * 0.5}
		im.DrawList_AddTextImFontPtr(
			dl,
			FONT_ICONS,
			NAV_ICON_SIZE,
			icon_pos,
			col,
			icon_str(icon, &icon_buf),
		)
		return clicked
	}

	im.BeginGroup()
	defer im.EndGroup()

	if nav_btn(.ChevronLeft, "prev", page_info.current_page^ > 1) {
		page_info.current_page^ -= 1
	}

	im.SameLine(0, 3)
	im.PushFontFloat(FONT_MEDIUM, FONT_SIZE_XS)
	im.Text(
		strings.clone_to_cstring(
			fmt.tprintf("%d", page_info.current_page^),
			context.temp_allocator,
		),
	)
	im.PopFont()

	im.SameLine(0, 3)
	im.TextDisabled("of")

	im.SameLine(0, 3)
	im.PushFontFloat(FONT_MEDIUM, FONT_SIZE_XS)
	im.Text(
		strings.clone_to_cstring(
			fmt.tprintf("%d", page_info.total_pages^),
			context.temp_allocator,
		),
	)
	im.PopFont()

	im.SameLine(0, 3)
	if nav_btn(.ChevronRight, "next", page_info.current_page^ < page_info.total_pages^) {
		page_info.current_page^ += 1
	}
}
