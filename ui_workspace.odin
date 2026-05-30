package main

import "core:c"
import "core:fmt"
import "core:strings"
import "core:time"
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


	switch conn in state.conn {

	// ── PostgreSQL ────────────────────────────────────────────────────────────
	case PQ_Conn:
		pg_conn := conn

		if !dbs_loaded || state.db_needs_reload {
			dbs, err := pg_get_dbs(pg_conn)
			if err != nil {panic(err.(DB_OpenFailed).message)}
			loaded_dbs = dbs
			dbs_loaded = true
			state.db_needs_reload = false
			pg_major_version = pg_server_version_major(pg_conn)
			current_db := pg_current_db(pg_conn)
			selected_db =
				current_db if current_db != "" else (loaded_dbs[0] if len(loaded_dbs) > 0 else "")
			prev_selected_db = selected_db
			schemas_loaded = false
			selected_schema = ""
			prev_selected_schema = ""
			loaded_tables = {}
			tables_loaded = false
			selected_table = ""
			query_result = {}
			prev_selected_table = ""
		}

		if selected_db != prev_selected_db {
			new_conn, err := pg_connect_to_db(pg_conn, selected_db)
			if err == nil {
				state.conn = new_conn
				pg_conn = new_conn
				schemas_loaded = false
			} else {
				loaded_schemas = {}
				schemas_loaded = true
			}
			selected_schema = ""
			prev_selected_schema = ""
			loaded_tables = {}
			tables_loaded = false
			selected_table = ""
			query_result = {}
			prev_selected_table = ""
			prev_selected_db = selected_db
		}

		if !schemas_loaded {
			schemas, err := pg_get_schemas(pg_conn)
			if err == nil {
				loaded_schemas = schemas
				schemas_loaded = true
				selected_schema = loaded_schemas[0] if len(loaded_schemas) > 0 else ""
			}
		}

		if selected_schema != prev_selected_schema {
			loaded_tables = {}
			tables_loaded = false
			selected_table = ""
			query_result = {}
			prev_selected_table = ""
			if selected_schema != "" {
				tables, err := pg_get_tables(pg_conn, selected_schema)
				if err == nil {
					loaded_tables = tables
					tables_loaded = true
				}
			}
			prev_selected_schema = selected_schema
		}

		if selected_table != prev_selected_table {
			query_result = {}
			query_time_ms = 0
			if selected_table != "" && selected_schema != "" {
				q := fmt.tprintf(
					`SELECT * FROM "%s"."%s" LIMIT 1000`,
					selected_schema,
					selected_table,
				)
				t := time.tick_now()
				result, err := pg_run_query(pg_conn, q)
				query_time_ms = time.duration_milliseconds(time.tick_since(t))
				if err == nil {query_result = result}
			}
			prev_selected_table = selected_table
		}

		// Sidebar
		im.SetNextWindowPos({0, 0}, .Always)
		im.SetNextWindowSize({SIDEBAR_WIDTH, display.y - WORKSPACE_STATUS_BAR_H}, .Always)
		im.Begin("DBs", nil, {.NoMove, .NoResize, .NoCollapse, .NoScrollbar, .NoTitleBar})
		defer im.End()

		im.Text("Database")
		im.SetNextItemWidth(-1)
		db_label := strings.clone_to_cstring(
			selected_db if selected_db != "" else "Select database...",
		)
		defer delete(db_label)
		if im.BeginCombo("##db_select", db_label) {
			for db in loaded_dbs {
				cname := strings.clone_to_cstring(db)
				defer delete(cname)
				if im.Selectable(cname, selected_db == db) {
					selected_db = db
					loaded_schemas = nil
					schemas_loaded = false
					tables_loaded = false
					loaded_tables = nil
				}
			}
			im.EndCombo()
		}

		im.Spacing()
		im.Text("Schema")
		im.SetNextItemWidth(-1)
		schema_label := strings.clone_to_cstring(
			selected_schema if selected_schema != "" else "Select schema...",
		)
		defer delete(schema_label)
		if im.BeginCombo("##schema_select", schema_label) {
			for s in loaded_schemas {
				cname := strings.clone_to_cstring(s)
				defer delete(cname)
				if im.Selectable(cname, selected_schema == s) {
					selected_schema = s
				}
			}
			im.EndCombo()
		}

		im.Spacing()
		im.Text("Tables")
		im.BeginChild("##tables_list", {-1, -1}, {.Borders})
		for tbl in loaded_tables {
			cname := strings.clone_to_cstring(tbl)
			defer delete(cname)
			if im.Selectable(cname, selected_table == tbl) {
				selected_table = tbl
			}
		}
		im.EndChild()

	// ── SQLite ────────────────────────────────────────────────────────────────
	case SQLite_Conn:
		sq_conn := conn

		if !tables_loaded || state.db_needs_reload {
			state.db_needs_reload = false
			loaded_tables = sqlite_get_tables(sq_conn)
			tables_loaded = true
			selected_table = ""
			query_result = {}
			prev_selected_table = ""
		}

		if selected_table != prev_selected_table {
			query_result = {}
			query_time_ms = 0
			if selected_table != "" {
				q := fmt.tprintf(`SELECT * FROM "%s" LIMIT 1000`, selected_table)
				t := time.tick_now()
				result, err := sqlite_run_query(sq_conn, q)
				query_time_ms = time.duration_milliseconds(time.tick_since(t))
				if err == nil {query_result = result}
			}
			prev_selected_table = selected_table
		}

		// Sidebar
		im.SetNextWindowPos({0, 0}, .Always)
		im.SetNextWindowSize({SIDEBAR_WIDTH, display.y - WORKSPACE_STATUS_BAR_H}, .Always)
		im.Begin("Tables", nil, {.NoMove, .NoResize, .NoCollapse, .NoScrollbar, .NoTitleBar})
		defer im.End()

		im.Text("Tables")
		im.BeginChild("##tables_list", {-1, -1}, {.Borders})
		for tbl in loaded_tables {
			cname := strings.clone_to_cstring(tbl)
			defer delete(cname)
			if im.Selectable(cname, selected_table == tbl) {
				selected_table = tbl
			}
		}
		im.EndChild()
	}

	// ── Shared content area ───────────────────────────────────────────────────
	im.SetNextWindowPos({SIDEBAR_WIDTH, 0}, .Always)
	im.SetNextWindowSize({display.x - SIDEBAR_WIDTH, display.y - WORKSPACE_STATUS_BAR_H}, .Always)
	im.Begin(
		"##content",
		nil,
		{.NoMove, .NoResize, .NoCollapse, .NoTitleBar, .NoScrollbar, .NoScrollWithMouse},
	)
	defer im.End()

	// Breadcrumb + toolbar
	style := im.GetStyle()
	if selected_db != "" {
		db_c := strings.clone_to_cstring(selected_db)
		defer delete(db_c)
		im.Text(db_c)
	}
	if selected_schema != "" {
		im.SameLine()
		im.TextDisabled("/")
		im.SameLine()
		sch_c := strings.clone_to_cstring(selected_schema)
		defer delete(sch_c)
		im.Text(sch_c)
	}
	if selected_table != "" {
		if selected_db != "" || selected_schema != "" {
			im.SameLine()
			im.TextDisabled("/")
			im.SameLine()
		}
		tbl_c := strings.clone_to_cstring(selected_table)
		defer delete(tbl_c)
		im.Text(tbl_c)
	}
	im.SameLine()
	im.Button("Data")

	refresh_lbl: cstring = "↻"
	row_lbl: cstring = "+ Row"
	refresh_w := im.CalcTextSize(refresh_lbl).x + style.FramePadding.x * 2
	row_w := im.CalcTextSize(row_lbl).x + style.FramePadding.x * 2
	right_x :=
		im.GetWindowWidth() - style.WindowPadding.x - row_w - refresh_w - style.ItemSpacing.x
	im.SameLine(right_x)
	if im.Button(refresh_lbl) {
		prev_selected_table = ""
	}
	im.SameLine()
	im.Button(row_lbl)

	im.Separator()

	if selected_table != "" && len(query_result.headers) > 0 {
		col_count := c.int(len(query_result.headers))
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
			for header in query_result.headers {
				cheader := strings.clone_to_cstring(header)
				defer delete(cheader)
				im.TableSetupColumn(cheader)
			}
			im.TableHeadersRow()
			for row in query_result.rows {
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

	// ── Status bar ────────────────────────────────────────────────────────────
	sb_props := StatusBar_Props {
		y_pos            = display.y - WORKSPACE_STATUS_BAR_H,
		display_w        = display.x,
		query_time_ms    = f32(query_time_ms),
		state            = state,
		pg_major_version = pg_major_version,
	}
	StatusBar(&sb_props)
}

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
	padding_y := (WORKSPACE_STATUS_BAR_H + 3 - im.GetTextLineHeight()) / 2
	im.PushStyleVarY(.WindowPadding, padding_y)

	defer im.PopStyleVar(2)

	im.Begin(
		"##statusbar",
		nil,
		{.NoMove, .NoResize, .NoCollapse, .NoTitleBar, .NoScrollbar, .NoScrollWithMouse},
	)
	defer im.End()
	center_y := (WORKSPACE_STATUS_BAR_H - im.GetTextLineHeight()) / 2
	im.SetCursorPosY(center_y)

	im.PushFont(FONT_REGULAR_SM)
	defer im.PopFont()
	connection_status_text(props.conn_status, props.pg_major_version, props.state)

	style := im.GetStyle()
	latency_lbl := strings.clone_to_cstring(
		fmt.tprintf("%d ms", props.state.latency),
		context.temp_allocator,
	)
	latency_w := im.CalcTextSize(latency_lbl).x
	im.SameLine(WORKSPACE_SIDEBAR_WIDTH - latency_w - style.WindowPadding.x)
	im.TextDisabled(latency_lbl)

	draw_list := im.GetWindowDrawList()
	x := WORKSPACE_SIDEBAR_WIDTH
	p0 := im.Vec2{im.GetWindowPos().x + x, im.GetWindowPos().y}
	p1 := im.Vec2{im.GetWindowPos().x + x, im.GetWindowPos().y + WORKSPACE_STATUS_BAR_H}
	im.DrawList_AddLine(draw_list, p0, p1, im.GetColorU32(.Separator), 1.0)

	im.PushStyleColor(.Separator, im.GetColorU32(.Separator))
	defer im.PopStyleColor()

	im.SameLine(WORKSPACE_SIDEBAR_WIDTH + style.WindowPadding.x)
	number_of_rows_text(103, 1000)

	im.SameLine()
	im.SeparatorEx({.Vertical})

	im.SameLine()
	im.PushFont(FONT_MEDIUM_SM)
	im.Text("1")
	im.PopFont()
	im.SameLine(0, 3)
	im.TextDisabled("Selected")

	if props.query_time_ms > 0 {
		im.SameLine()
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


	readonly_lbl: cstring = "Read-only Off"
	readonly_w := im.CalcTextSize(readonly_lbl).x
	readonly_pos := props.display_w - readonly_w - style.WindowPadding.x
	im.SameLine(readonly_pos)
	im.TextDisabled(readonly_lbl)

	im.SameLine(readonly_pos - style.WindowPadding.x)
	im.SeparatorEx({.Vertical})

	encoding_type_lbl: cstring = "UTF8"
	encoding_type_w := im.CalcTextSize(encoding_type_lbl).x
	encoding_type_pos := readonly_pos - style.WindowPadding.x * 2 - encoding_type_w
	im.SameLine(encoding_type_pos)
	im.TextDisabled(encoding_type_lbl)

	im.SameLine(encoding_type_pos - style.WindowPadding.x)
	im.SeparatorEx({.Vertical})

	pages_lbl: cstring = "<1-14>"
	pages_w := im.CalcTextSize(pages_lbl).x
	pages_pos := encoding_type_pos - style.WindowPadding.x * 2 - pages_w
	im.SameLine(pages_pos)
	im.TextDisabled(pages_lbl)
}

connection_status_text :: proc(
	conn_status: ConnectionStatus,
	pg_major_version: i32,
	state: ^App_State,
) {
	draw_list := im.GetWindowDrawList()
	p := im.GetCursorScreenPos()
	connection_indicator_pos_x := p.x + 6
	im.DrawList_AddCircleFilled(
		draw_list,
		{connection_indicator_pos_x, p.y + 8},
		3,
		im.GetColorU32ImVec4({0.13, 0.75, 0.33, 1.0}),
	)

	im.SameLine()
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
	im.DrawList_AddCircleFilled(
		draw_list,
		{connection_indicator_pos_x + status_label_w + 12, p.y + 8},
		2,
		im.GetColorU32(.Separator),
	)

	im.Dummy({12, 0})
	im.SameLine(0, 1)
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
