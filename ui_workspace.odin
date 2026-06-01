package main

import "core:c"
import "core:strings"
import im "vendor/odin-imgui"

WORKSPACE_SIDEBAR_WIDTH: f32 = 260
WORKSPACE_STATUS_BAR_H :: f32(24)

UIWorkspace :: proc(state: ^App_State) {
	// Postgres-only
	@(static) loaded_dbs: []string
	@(static) dbs_loaded: bool
	@(static) selected_db: string
	@(static) prev_selected_db: string
	@(static) loaded_schemas: []string
	@(static) schemas_loaded: bool
	@(static) selected_schema: string
	@(static) prev_selected_schema: string

	// Shared
	@(static) loaded_tables: []string
	@(static) tables_loaded: bool
	@(static) selected_table: string
	@(static) query_result: QueryResult
	@(static) prev_selected_table: string
	@(static) query_time_ms: f64
	@(static) pg_major_version: i32

	display := im.GetIO().DisplaySize

	Workspace_Sidebar(
		{
			state = state,
			display_h = display.y,
			loaded_dbs = &loaded_dbs,
			dbs_loaded = &dbs_loaded,
			selected_db = &selected_db,
			prev_selected_db = &prev_selected_db,
			loaded_schemas = &loaded_schemas,
			schemas_loaded = &schemas_loaded,
			selected_schema = &selected_schema,
			prev_selected_schema = &prev_selected_schema,
			loaded_tables = &loaded_tables,
			tables_loaded = &tables_loaded,
			selected_table = &selected_table,
			query_result = &query_result,
			prev_selected_table = &prev_selected_table,
			query_time_ms = &query_time_ms,
			pg_major_version = &pg_major_version,
		},
	)

	im.SetNextWindowPos({SIDEBAR_WIDTH, 0}, .Always)
	im.SetNextWindowSize({display.x - SIDEBAR_WIDTH, display.y - WORKSPACE_STATUS_BAR_H}, .Always)

	im.PushStyleVar(.WindowBorderSize, 0)
	defer im.PopStyleVar()

	im.Begin(
		"##content",
		nil,
		{.NoMove, .NoResize, .NoCollapse, .NoTitleBar, .NoScrollbar, .NoScrollWithMouse},
	)
	defer im.End()

	cp := Workspace_ContentProps {
		selected_db         = &selected_db,
		selected_schema     = &selected_schema,
		selected_table      = &selected_table,
		prev_selected_table = &prev_selected_table,
		query_result        = &query_result,
	}
	Workspace_Content(&cp)

	sb_props := StatusBar_Props {
		y_pos            = display.y - WORKSPACE_STATUS_BAR_H,
		display_w        = display.x,
		query_time_ms    = f32(query_time_ms),
		state            = state,
		pg_major_version = pg_major_version,
	}
	StatusBar(&sb_props)
}

Workspace_ContentProps :: struct {
	selected_db:         ^string,
	selected_schema:     ^string,
	selected_table:      ^string,
	prev_selected_table: ^string,
	query_result:        ^QueryResult,
}

Workspace_Content :: proc(props: ^Workspace_ContentProps) {
	// Push shared button style once for the whole toolbar so
	// AlignTextToFramePadding centers text to the same vertical midpoint
	// as the buttons (FramePadding.y = 2).
	im.PushStyleVar(.FrameBorderSize, 1.0)
	im.PushStyleVar(.FrameRounding, 4)
	im.PushStyleVarImVec2(.FramePadding, {10, 2})
	im.PushStyleColorImVec4(.Button, COLOR_BACKGROUND)
	im.PushStyleColorImVec4(.ButtonHovered, COLOR_MUTED_BACKGROUND)
	im.PushStyleColorImVec4(.ButtonActive, COLOR_MUTED_BACKGROUND)

	im.AlignTextToFramePadding()

	// Breadcrumb
	im.PushFont(FONT_REGULAR_SM)
	im.PushStyleColorImVec4(.Text, COLOR_MUTED_FOREGROUND)
	if props.selected_db^ != "" {
		db_c := strings.clone_to_cstring(props.selected_db^)
		defer delete(db_c)
		im.Text(db_c)
	}
	if props.selected_schema^ != "" {
		im.SameLine()
		im.TextDisabled("/")
		im.SameLine()
		sch_c := strings.clone_to_cstring(props.selected_schema^)
		defer delete(sch_c)
		im.Text(sch_c)
	}
	im.PopStyleColor()
	im.PopFont()

	im.PushFont(FONT_MEDIUM_SM)
	if props.selected_table^ != "" {
		if props.selected_db^ != "" || props.selected_schema^ != "" {
			im.SameLine()
			im.TextDisabled("/")
			im.SameLine()
		}
		tbl_c := strings.clone_to_cstring(props.selected_table^)
		defer delete(tbl_c)
		im.Text(tbl_c)
	}
	im.PopFont()

	// Toolbar buttons — inherit shared style, no per-button push/pop needed.
	style := im.GetStyle()

	refresh_buf: [5]u8
	refresh_s := icon_str(.Refresh, &refresh_buf)
	plus_buf: [5]u8
	plus_s := icon_str(.Plus, &plus_buf)

	im.PushFont(FONT_ICONS)
	icon_native_w := im.CalcTextSize(plus_s).x
	im.PopFont()
	plus_icon_w := icon_native_w * (ICON_SIZE / 16.0)

	btn_h := im.GetFrameHeight()
	refresh_w := ICON_SIZE + style.FramePadding.x * 2
	row_text_sz := im.CalcTextSize("Row")
	row_w := plus_icon_w + 4 + row_text_sz.x + style.FramePadding.x * 2
	right_x :=
		im.GetWindowWidth() - style.WindowPadding.x - row_w - refresh_w - style.ItemSpacing.x

	im.SameLine()
	im.Button("Data")

	// Refresh button
	im.SameLine(right_x)
	{
		pos := im.GetCursorScreenPos()
		im.InvisibleButton("##refresh", {refresh_w, btn_h})
		hovered := im.IsItemHovered()
		clicked := im.IsItemClicked()
		if clicked {props.prev_selected_table^ = ""}
		dl := im.GetWindowDrawList()
		bg := im.GetColorU32ImVec4(COLOR_MUTED_BACKGROUND if hovered else COLOR_BACKGROUND)
		im.DrawList_AddRectFilled(dl, pos, {pos.x + refresh_w, pos.y + btn_h}, bg, 4)
		im.DrawList_AddRect(
			dl,
			pos,
			{pos.x + refresh_w, pos.y + btn_h},
			im.GetColorU32ImVec4(COLOR_BORDER),
			4,
		)
		im.DrawList_AddTextImFontPtr(
			dl,
			FONT_ICONS,
			ICON_SIZE,
			{pos.x + style.FramePadding.x, pos.y + (btn_h - ICON_SIZE) * 0.5},
			im.GetColorU32(.Text),
			refresh_s,
		)
	}

	// + Row button
	im.SameLine()
	{
		pos := im.GetCursorScreenPos()
		im.InvisibleButton("##add_row", {row_w, btn_h})

		hovered := im.IsItemHovered()
		dl := im.GetWindowDrawList()
		bg := im.GetColorU32ImVec4(COLOR_MUTED_BACKGROUND if hovered else COLOR_BACKGROUND)
		im.DrawList_AddRectFilled(dl, pos, {pos.x + row_w, pos.y + btn_h}, bg, 4)
		im.DrawList_AddRect(
			dl,
			pos,
			{pos.x + row_w, pos.y + btn_h},
			im.GetColorU32ImVec4(COLOR_BORDER),
			4,
		)
		icon_x := pos.x + style.FramePadding.x
		im.DrawList_AddTextImFontPtr(
			dl,
			FONT_ICONS,
			ICON_SIZE,
			{icon_x, pos.y + (btn_h - ICON_SIZE) * 0.5},
			im.GetColorU32(.Text),
			plus_s,
		)
		im.DrawList_AddText(
			dl,
			{icon_x + plus_icon_w + 4, pos.y + (btn_h - row_text_sz.y) * 0.5},
			im.GetColorU32(.Text),
			"Row",
		)
	}

	im.PopStyleColor(3)
	im.PopStyleVar(3)

	{
		dl := im.GetWindowDrawList()
		y := im.GetCursorScreenPos().y
		x := im.GetWindowPos().x
		im.DrawList_AddLine(
			dl,
			{x, y},
			{x + im.GetWindowWidth(), y},
			im.GetColorU32(.Separator),
			1.0,
		)
		im.Dummy({0, 1})
	}

	im.TextDisabled("where")

	im.SameLine(0, 6)
	{
		PAD_X :: f32(8)
		PAD_Y :: f32(4)
		SPACING :: f32(4)
		DASH :: f32(4)
		GAP :: f32(3)
		ROUNDING :: f32(4)

		icon_buf: [5]u8
		icon_s := icon_str(.Filter, &icon_buf)
		im.PushFont(FONT_ICONS)
		native := im.CalcTextSize(icon_s)
		im.PopFont()
		scale := ICON_SIZE / 16.0
		icon_w := native.x * scale
		icon_h := native.y * scale
		label_sz := im.CalcTextSize("Filter")

		btn_w := PAD_X * 2 + icon_w + SPACING + label_sz.x
		btn_h := PAD_Y * 2 + label_sz.y

		pos := im.GetCursorScreenPos()
		im.InvisibleButton("##add_filter", {btn_w, btn_h})
		hovered := im.IsItemHovered()

		dl := im.GetWindowDrawList()
		x1 := pos.x
		y1 := pos.y
		x2 := x1 + btn_w
		y2 := y1 + btn_h
		col := im.GetColorU32ImVec4(COLOR_BORDER)

		// Dashed edges — each truncated by ROUNDING at both ends so the
		// corners are left clear for the arc segments below.
		{x, on := x1 + ROUNDING, true
			for x <
			    x2 -
				    ROUNDING {nx := min(x + (DASH if on else GAP), x2 - ROUNDING); if on {im.DrawList_AddLine(dl, {x, y1}, {nx, y1}, col)}; x, on = nx, !on}}
		{x, on := x1 + ROUNDING, true
			for x <
			    x2 -
				    ROUNDING {nx := min(x + (DASH if on else GAP), x2 - ROUNDING); if on {im.DrawList_AddLine(dl, {x, y2}, {nx, y2}, col)}; x, on = nx, !on}}
		{y, on := y1 + ROUNDING, true
			for y <
			    y2 -
				    ROUNDING {ny := min(y + (DASH if on else GAP), y2 - ROUNDING); if on {im.DrawList_AddLine(dl, {x1, y}, {x1, ny}, col)}; y, on = ny, !on}}
		{y, on := y1 + ROUNDING, true
			for y <
			    y2 -
				    ROUNDING {ny := min(y + (DASH if on else GAP), y2 - ROUNDING); if on {im.DrawList_AddLine(dl, {x2, y}, {x2, ny}, col)}; y, on = ny, !on}}

		// Rounded corners using PathArcToFast (12-step circle: 0=0°, 3=90°, 6=180°, 9=270°)
		im.DrawList_PathClear(
			dl,
		); im.DrawList_PathArcToFast(dl, {x1 + ROUNDING, y1 + ROUNDING}, ROUNDING, 6, 9); im.DrawList_PathStroke(dl, col)
		im.DrawList_PathClear(
			dl,
		); im.DrawList_PathArcToFast(dl, {x2 - ROUNDING, y1 + ROUNDING}, ROUNDING, 9, 12); im.DrawList_PathStroke(dl, col)
		im.DrawList_PathClear(
			dl,
		); im.DrawList_PathArcToFast(dl, {x2 - ROUNDING, y2 - ROUNDING}, ROUNDING, 0, 3); im.DrawList_PathStroke(dl, col)
		im.DrawList_PathClear(
			dl,
		); im.DrawList_PathArcToFast(dl, {x1 + ROUNDING, y2 - ROUNDING}, ROUNDING, 3, 6); im.DrawList_PathStroke(dl, col)

		text_color := im.GetColorU32ImVec4(COLOR_MUTED_FOREGROUND)
		im.DrawList_AddTextImFontPtr(
			dl,
			FONT_ICONS,
			ICON_SIZE,
			{x1 + PAD_X, y1 + (btn_h - icon_h) * 0.5},
			text_color,
			icon_s,
		)
		im.DrawList_AddText(
			dl,
			{x1 + PAD_X + icon_w + SPACING, y1 + (btn_h - label_sz.y) * 0.5},
			text_color,
			"Filter",
		)
	}

	{
		dl := im.GetWindowDrawList()
		y := im.GetCursorScreenPos().y
		x := im.GetWindowPos().x
		im.DrawList_AddLine(
			dl,
			{x, y},
			{x + im.GetWindowWidth(), y},
			im.GetColorU32(.Separator),
			1.0,
		)
		im.Dummy({0, 1})
	}

	if props.selected_table^ != "" && len(props.query_result^.headers) > 0 {
		col_count := c.int(len(props.query_result^.headers))
		table_flags :=
			im.TableFlags_BordersInner |
			im.TableFlags_NoPadOuterX |
			im.TableFlags_RowBg |
			im.TableFlags_ScrollX |
			im.TableFlags_ScrollY |
			im.TableFlags_Resizable |
			im.TableFlags_Reorderable


		im.PushStyleColorImVec4(.TableBorderLight, COLOR_BORDER)
		avail := im.GetContentRegionAvail()
		if im.BeginTable("##tabledata", col_count, table_flags, avail) {
			im.TableSetupScrollFreeze(0, 1)

			for header in props.query_result^.headers {
				cheader := strings.clone_to_cstring(header)
				defer delete(cheader)
				im.TableSetupColumn(cheader)
			}

			im.PushFont(FONT_MEDIUM)
			im.PushStyleColorImVec4(.TableHeaderBg, COLOR_MUTED_BACKGROUND)
			im.PushStyleColorImVec4(.Text, COLOR_MUTED_FOREGROUND)
			im.TableNextRow({.Headers})

			for header, col in props.query_result^.headers {
				im.TableSetColumnIndex(c.int(col))
				cheader := strings.clone_to_cstring(header)
				defer delete(cheader)
				im.TableHeader(cheader)
			}

			im.PopStyleColor(2)
			im.PopFont()

			for row in props.query_result^.rows {
				im.TableNextRow()
				for cell, col in row {
					im.TableSetColumnIndex(c.int(col))
					ccell := strings.clone_to_cstring(cell)
					defer delete(ccell)
					im.TextUnformatted(ccell)
				}
			}
			im.EndTable()
		}
		im.PopStyleColor() // TableBorderLight
	}
}
