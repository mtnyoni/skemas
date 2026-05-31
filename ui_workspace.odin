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
	// Breadcrumb + toolbar
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

	im.SameLine()
	im.Button("Data")

	style := im.GetStyle()
	refresh_lbl: cstring = "↻"
	row_lbl: cstring = "+ Row"
	refresh_w := im.CalcTextSize(refresh_lbl).x + style.FramePadding.x * 2
	row_w := im.CalcTextSize(row_lbl).x + style.FramePadding.x * 2
	right_x :=
		im.GetWindowWidth() - style.WindowPadding.x - row_w - refresh_w - style.ItemSpacing.x
	im.SameLine(right_x)
	if im.Button(refresh_lbl) {
		props.prev_selected_table^ = ""
	}
	im.SameLine()
	im.Button(row_lbl)

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
			im.TableFlags_Borders |
			im.TableFlags_RowBg |
			im.TableFlags_ScrollX |
			im.TableFlags_ScrollY |
			im.TableFlags_Resizable |
			im.TableFlags_Reorderable
		avail := im.GetContentRegionAvail()
		if im.BeginTable("##tabledata", col_count, table_flags, avail) {
			im.TableSetupScrollFreeze(0, 1)
			for header in props.query_result^.headers {
				cheader := strings.clone_to_cstring(header)
				defer delete(cheader)
				im.TableSetupColumn(cheader)
			}
			im.TableHeadersRow()
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
	}
}
