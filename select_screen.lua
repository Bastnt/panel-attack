local select_screen = {}

select_screen.fallback_when_missing = { nil, nil }
select_screen.character_select_mode = "1p_vs_yourself"

local wait = coroutine.yield
local current_page = 1

-- fills the provided map based on the provided template and return the amount of pages. __Empty values will be replaced by character_ids
local function fill_map(template_map,map)
  local X,Y = 5,9
  local pages_amount = 0
  local character_id_index = 1
  while true do
    -- new page handling
    pages_amount = pages_amount+1
    map[pages_amount] = deepcpy(template_map)

    -- go through the page and replace __Empty with characters_ids_for_current_theme
    for i=1,X do
      for j=1,Y do
        if map[pages_amount][i][j] == "__Empty" then
          map[pages_amount][i][j] = characters_ids_for_current_theme[character_id_index]
          character_id_index = character_id_index+1
          -- end case: no more characters_ids_for_current_theme to add
          if character_id_index == #characters_ids_for_current_theme+1 then
            print("filled "..#characters_ids_for_current_theme.." characters across "..pages_amount.." page(s)")
            return pages_amount
          end
        end
      end
    end
  end
end

function refresh_based_on_own_mods(refreshed,ask_change_fallback)
  ask_change_fallback = ask_change_fallback or false
  if refreshed ~= nil then
    -- panels
    if refreshed.panels_dir == nil or panels[refreshed.panels_dir] == nil then
      refreshed.panels_dir = config.panels
    end

    -- stage
    if refreshed.stage == nil or ( refreshed.stage ~= random_stage_special_value and stages[refreshed.stage] == nil ) then
      if not select_screen.fallback_when_missing[1] or ask_change_fallback then
        select_screen.fallback_when_missing[1] = uniformly(stages_ids_for_current_theme)
      end
      refreshed.stage = select_screen.fallback_when_missing[1]
    end

    -- character
    if refreshed.character == nil or ( refreshed.character ~= random_character_special_value and characters[refreshed.character] == nil ) then
      if refreshed.character_display_name and characters_ids_by_display_names[refreshed.character_display_name] then
        refreshed.character = characters_ids_by_display_names[refreshed.character_display_name][1]
      else
        if not select_screen.fallback_when_missing[2] or ask_change_fallback then
          select_screen.fallback_when_missing[2] = uniformly(characters_ids_for_current_theme)
        end
        refreshed.character = select_screen.fallback_when_missing[2]
      end
    end
  end
end

function select_screen.main()
  if themes[config.theme].musics.select_screen then
    stop_the_music()
    find_and_add_music(themes[config.theme].musics, "select_screen")
  elseif themes[config.theme].musics.main then
    find_and_add_music(themes[config.theme].musics, "main")
  end

  bg = themes[config.theme].images.bg_select_screen

  select_screen.fallback_when_missing = { nil, nil }

  local function add_client_data(state)
    state.loaded = characters[state.character] and characters[state.character].fully_loaded and stages[state.stage] and stages[state.stage].fully_loaded
    state.wants_ready = state.ready
  end

  local function refresh_loaded_and_ready(state_1,state_2)
    state_1.loaded = characters[state_1.character] and characters[state_1.character].fully_loaded and stages[state_1.stage] and stages[state_1.stage].fully_loaded
    if state_2 then
      state_2.loaded = characters[state_2.character] and characters[state_2.character].fully_loaded and stages[state_2.stage] and stages[state_2.stage].fully_loaded
    end
    
    if select_screen.character_select_mode == "2p_net_vs" then
      state_1.ready = state_1.wants_ready and state_1.loaded and state_2.loaded
    else
      state_1.ready = state_1.wants_ready and state_1.loaded
      if state_2 then
        state_2.ready = state_2.wants_ready and state_2.loaded
      end
    end
  end

  -- map is composed of special values prefixed by __ and character ids
  local template_map = {{"__Panels", "__Panels", "__Stage", "__Stage", "__Stage", "__Level", "__Level", "__Level", "__Ready"},
             {"__Random", "__Empty", "__Empty", "__Empty", "__Empty", "__Empty", "__Empty", "__Empty", "__Empty"},
             {"__Empty", "__Empty", "__Empty", "__Empty", "__Empty", "__Empty", "__Empty", "__Empty", "__Empty"},
             {"__Empty", "__Empty", "__Empty", "__Empty", "__Empty", "__Empty", "__Empty", "__Empty", "__Empty"},
             {"__Empty", "__Empty", "__Empty", "__Empty", "__Empty", "__Empty", "__Empty", "__Empty", "__Leave"}}
  local map = {}
  if select_screen.character_select_mode == "2p_net_vs" then
    local opponent_connected = false
    local retries, retry_limit = 0, 250
    while not global_initialize_room_msg and retries < retry_limit do
      local msg = server_queue:pop_next_with("create_room", "character_select", "spectate_request_granted")
      if msg then
        global_initialize_room_msg = msg
      end
      gprint(loc("ss_init"), unpack(main_menu_screen_pos))
      wait()
      if not do_messages() then
        return main_dumb_transition, {main_select_mode, loc("ss_disconnect").."\n\n"..loc("ss_return"), 60, 300}
      end
      retries = retries + 1
    end
    -- if room_number_last_spectated and retries >= retry_limit and currently_spectating then
      -- request_spectate(room_number_last_spectated)
      -- retries = 0
      -- while not global_initialize_room_msg and retries < retry_limit do
        -- for _,msg in ipairs(this_frame_messages) do
          -- if msg.create_room or msg.character_select or msg.spectate_request_granted then
            -- global_initialize_room_msg = msg
          -- end
        -- end
        -- gprint("Lost connection.  Trying to rejoin...", unpack(main_menu_screen_pos))
        -- wait()
        -- if not do_messages() then
        --   return main_dumb_transition, {main_select_mode, "Disconnected from server.\n\nReturning to main menu...", 60, 300}
        -- end
        -- retries = retries + 1
      -- end
    -- end
    if not global_initialize_room_msg then
      return main_dumb_transition, {main_select_mode, loc("ss_init_fail").."\n\n"..loc("ss_return"), 60, 300}
    end
    msg = global_initialize_room_msg
    if msg.ratings then
        global_current_room_ratings = msg.ratings
    end

    if msg.your_player_number then
      my_player_number = msg.your_player_number
    elseif currently_spectating then
      my_player_number = 1
    elseif my_player_number and my_player_number ~= 0 then
      print("We assumed our player number is still "..my_player_number)
    else
      error(loc("nt_player_err"))
      print("Error: The server never told us our player number.  Assuming it is 1")
      my_player_number = 1
    end

    if msg.op_player_number then
      op_player_number = msg.op_player_number or op_player_number
    elseif currently_spectating then
      op_player_number = 2
    elseif op_player_number and op_player_number ~= 0 then
      print("We assumed op player number is still "..op_player_number)
    else
      error("We never heard from the server as to what player number we are")
      print("Error: The server never told us our player number.  Assuming it is 2")
      op_player_number = 2
    end

    if my_player_number == 2 and msg.a_menu_state ~= nil and msg.b_menu_state ~= nil then
      print("inverting the states to match player number!")
      msg.a_menu_state, msg.b_menu_state = msg.b_menu_state, msg.a_menu_state
    end

    global_my_state = msg.a_menu_state
    refresh_based_on_own_mods(global_my_state)
    global_op_state = msg.b_menu_state
    refresh_based_on_own_mods(global_op_state)

    if msg.win_counts then
      update_win_counts(msg.win_counts)
    end
    if msg.replay_of_match_so_far then
      replay_of_match_so_far = msg.replay_of_match_so_far
    end
    if msg.ranked then
      match_type = "Ranked"
      match_type_message = ""
    else
      match_type = "Casual"
    end
    if currently_spectating then
      P1 = {panel_buffer="", gpanel_buffer=""}
      print("we reset P1 buffers at start of main_character_select()")
    end
    P2 = {panel_buffer="", gpanel_buffer=""}
    print("we reset P2 buffers at start of main_character_select()")
    print("current_server_supports_ranking: "..tostring(current_server_supports_ranking))

    if current_server_supports_ranking then
      template_map = {{"__Panels", "__Panels", "__Mode", "__Mode", "__Stage", "__Stage", "__Level", "__Level", "__Ready"},
             {"__Random", "__Empty", "__Empty", "__Empty", "__Empty", "__Empty", "__Empty", "__Empty", "__Empty"},
             {"__Empty", "__Empty", "__Empty", "__Empty", "__Empty", "__Empty", "__Empty", "__Empty", "__Empty"},
             {"__Empty", "__Empty", "__Empty", "__Empty", "__Empty", "__Empty", "__Empty", "__Empty", "__Empty"},
             {"__Empty", "__Empty", "__Empty", "__Empty", "__Empty", "__Empty", "__Empty", "__Empty", "__Leave"}}
    end
  end

  local pages_amount = fill_map(template_map, map)
  if current_page > pages_amount then
    current_page = 1
  end

  op_win_count = op_win_count or 0

  if select_screen.character_select_mode == "2p_net_vs" then
    global_current_room_ratings = global_current_room_ratings or {{new=0,old=0,difference=0},{new=0,old=0,difference=0}}
    my_expected_win_ratio = nil
    op_expected_win_ratio = nil
    print("my_player_number = "..my_player_number)
    print("op_player_number = "..op_player_number)
    if global_current_room_ratings[my_player_number].new
    and global_current_room_ratings[my_player_number].new ~= 0
    and global_current_room_ratings[op_player_number]
    and global_current_room_ratings[op_player_number].new ~= 0 then
      my_expected_win_ratio = (100*round(1/(1+10^
            ((global_current_room_ratings[op_player_number].new
                -global_current_room_ratings[my_player_number].new)
              /RATING_SPREAD_MODIFIER))
            ,2))
      op_expected_win_ratio = (100*round(1/(1+10^
            ((global_current_room_ratings[my_player_number].new
                -global_current_room_ratings[op_player_number].new)
              /RATING_SPREAD_MODIFIER))
            ,2))
    end
    match_type = match_type or "Casual"
    if match_type == "" then match_type = "Casual" end
  end

  match_type_message = match_type_message or ""

  local function do_leave()
    stop_the_music()
    my_win_count = 0
    op_win_count = 0
    return json_send({leave_room=true})
  end

  -- be wary: name_to_xy_per_page is kinda buggy for larger blocks as they span multiple positions (we retain the last one), and is completely broken with __Empty
  local name_to_xy_per_page = {}
  local X,Y = 5,9
  for p=1,pages_amount do
    name_to_xy_per_page[p] = {}
    for i=1,X do
      for j=1,Y do
        if map[p][i][j] then
          name_to_xy_per_page[p][map[p][i][j]] = {i,j}
        end
      end
    end
  end

  my_win_count = my_win_count or 0

  local cursor_data = {{position=shallowcpy(name_to_xy_per_page[current_page]["__Ready"]),can_super_select=false,selected=false},{position=shallowcpy(name_to_xy_per_page[current_page]["__Ready"]),can_super_select=false,selected=false}}
  
  -- our data (first player in local)
  if global_my_state ~= nil then
    cursor_data[1].state = shallowcpy(global_my_state)
    global_my_state = nil
  else
    cursor_data[1].state = {stage=config.stage, stage_is_random=config.stage==random_stage_special_value, character=config.character, character_is_random=config.character==random_character_special_value, level=config.level, panels_dir=config.panels, cursor="__Ready", ready=false, ranked=config.ranked}
  end

  if cursor_data[1].state.character_is_random then
    cursor_data[1].state.character = uniformly(characters_ids_for_current_theme)
    character_loader_load(cursor_data[1].state.character)
  end
  cursor_data[1].state.character_display_name = characters[cursor_data[1].state.character].display_name
  if cursor_data[1].state.stage_is_random then
    cursor_data[1].state.stage = uniformly(stages_ids_for_current_theme)
  end

  stage_loader_load(cursor_data[1].state.stage)
  add_client_data(cursor_data[1].state)

  if select_screen.character_select_mode ~= "1p_vs_yourself" then
    if global_op_state ~= nil then
      cursor_data[2].state = shallowcpy(global_op_state)
      if select_screen.character_select_mode ~= "2p_local_vs" then
        global_op_state = nil -- retains state of the second player, also: don't unload its character when going back and forth
      else
        if cursor_data[2].state.character_is_random then
          cursor_data[2].state.character = uniformly(characters_ids_for_current_theme)
        end
        cursor_data[2].state.character_display_name = characters[cursor_data[2].state.character].display_name
        if cursor_data[2].state.stage_is_random then
          cursor_data[2].state.stage = uniformly(stages_ids_for_current_theme)
        end
      end
    else
      cursor_data[2].state = {stage=config.stage, stage_is_random=config.stage==random_stage_special_value, character=config.character, character_is_random=config.character==random_character_special_value, level=config.level, panels_dir=config.panels, cursor="__Ready", ready=false, ranked=false}
      if cursor_data[2].state.character_is_random then
        cursor_data[2].state.character = uniformly(characters_ids_for_current_theme)
      end
      cursor_data[2].state.character_display_name = characters[cursor_data[2].state.character].display_name
      if cursor_data[2].state.stage_is_random then
        cursor_data[2].state.stage = uniformly(stages_ids_for_current_theme)
      end
    end
    if cursor_data[2].state.character ~= random_character_special_value then -- while playing online, we'll wait for them to send us the new pick
      character_loader_load(cursor_data[2].state.character)
    end
    if cursor_data[2].state.stage ~= random_stage_special_value then -- while playing online, we'll wait for them to send us the new pick
      stage_loader_load(cursor_data[2].state.stage)
    end
    add_client_data(cursor_data[2].state)
  end
  refresh_loaded_and_ready(cursor_data[1].state, cursor_data[2] and cursor_data[2].state or nil)

  local prev_state = shallowcpy(cursor_data[1].state)

  local super_select_pixelcode = [[
      uniform float percent;
      vec4 effect( vec4 color, Image tex, vec2 texture_coords, vec2 screen_coords )
      {
          vec4 c = Texel(tex, texture_coords) * color;
          if( texture_coords.x < percent )
          {
            return c;
          }
          float ret = (c.x+c.y+c.z)/3.0;
          return vec4(ret, ret, ret, c.a);
      }
  ]]
 
  -- one per player, should we put them into cursor_data even though it's meaningless?
  local super_select_shaders = { love.graphics.newShader(super_select_pixelcode), love.graphics.newShader(super_select_pixelcode) }

  local function draw_button(x,y,w,h,str,halign,valign,no_rect)
    no_rect = no_rect or str == "__Empty" or str == "__Reserved"
    halign = halign or "center"
    valign = valign or "top"
    local menu_width = Y*100
    local menu_height = X*80
    local spacing = 8
    local text_height = 13
    local x_padding = math.floor((canvas_width-menu_width)/2)
    local y_padding = math.floor((canvas_height-menu_height)/2)
    set_color(unpack(colors.white))
    render_x = x_padding+(y-1)*100+spacing
    render_y = y_padding+(x-1)*100+spacing
    button_width = w*100-2*spacing
    button_height = h*100-2*spacing
    if no_rect == false then
      grectangle("line", render_x, render_y, button_width, button_height)
    end
    local character = characters[str]
    if str == "P1" then
      character = cursor_data[1].state.character_is_random and random_character_special_value or characters[cursor_data[1].state.character]
    elseif str == "P2" then
      character = cursor_data[2].state.character_is_random and random_character_special_value or characters[cursor_data[2].state.character]
    end
    local width_for_alignment = button_width
    local x_add,y_add = 0,0
    if valign == "center" then
      y_add = math.floor(0.5*button_height-0.5*text_height)-3
    elseif valign == "bottom" then
      y_add = math.floor(button_height-text_height)
    end
    if character then
      x_add = 0.025*button_width
      width_for_alignment = 0.95*button_width
      local icon_to_use = character == random_character_special_value and themes[config.theme].images.IMG_random_character or character.images["icon"]
      local orig_w, orig_h = icon_to_use:getDimensions()
      local scale = button_width/math.max(orig_w,orig_h) -- keep image ratio
      menu_drawf(icon_to_use, render_x+0.5*button_width, render_y+0.5*button_height,"center","center", 0, scale, scale )
      if str ~= "P1" and str ~= "P2" then
        if character.stage then
          local orig_w, orig_h = stages[character.stage].images.thumbnail:getDimensions()
          menu_drawf(stages[character.stage].images.thumbnail, render_x+10, render_y+button_height-7,"center","center", 0, 16/orig_w, 9/orig_h )
        end
        if character.panels then
          local orig_w, orig_h = panels[character.panels].images.classic[1][1]:getDimensions()
          menu_drawf(panels[character.panels].images.classic[1][1], render_x+7, character.stage and render_y+button_height-19 or render_y+button_height-6,"center","center", 0, 12/orig_w, 12/orig_h )
        end
      end
    end

    local function draw_super_select(player_num)
      local ratio = menu_pressing_enter(K[player_num])
      if ratio > super_selection_enable_ratio then
        super_select_shaders[player_num]:send("percent", linear_smooth(ratio,super_selection_enable_ratio,1.0))
        set_shader(super_select_shaders[player_num])
        menu_drawf(themes[config.theme].images.IMG_super, render_x+button_width*0.5, render_y+button_height*0.5, "center", "center" )
        set_shader()
      end
    end

    local function draw_cursor(button_height, spacing, player_num,ready)
      local cur_blink_frequency = 4
      local cur_pos_change_frequency = 8
      local draw_cur_this_frame = false
      local cursor_frame = 1
      if ready then
        if (math.floor(menu_clock/cur_blink_frequency)+player_num)%2+1 == player_num then
          draw_cur_this_frame = true
        end
      else
        draw_cur_this_frame = true
        cursor_frame = (math.floor(menu_clock/cur_pos_change_frequency)+player_num)%2+1
      end
      if draw_cur_this_frame then
        local cur_img = themes[config.theme].images.IMG_char_sel_cursors[player_num][cursor_frame]
        local cur_img_left = themes[config.theme].images.IMG_char_sel_cursor_halves.left[player_num][cursor_frame]
        local cur_img_right = themes[config.theme].images.IMG_char_sel_cursor_halves.right[player_num][cursor_frame]
        local cur_img_w, cur_img_h = cur_img:getDimensions()
        local cursor_scale = (button_height+(spacing*2))/cur_img_h
        menu_drawq(cur_img, cur_img_left, render_x-spacing, render_y-spacing, 0, cursor_scale , cursor_scale)
        menu_drawq(cur_img, cur_img_right, render_x+button_width+spacing-cur_img_w*cursor_scale/2, render_y-spacing, 0, cursor_scale, cursor_scale)
      end
    end

    local function draw_player_state(cursor_data,player_number)
      if characters[cursor_data.state.character] and not characters[cursor_data.state.character].fully_loaded then
        menu_drawf(themes[config.theme].images.IMG_loading, render_x+button_width*0.5, render_y+button_height*0.5, "center", "center" )
      elseif cursor_data.state.wants_ready then
        menu_drawf(themes[config.theme].images.IMG_ready, render_x+button_width*0.5, render_y+button_height*0.5, "center", "center" )
      end
      local scale = 0.25*button_width/math.max(themes[config.theme].images.IMG_players[player_number]:getWidth(),themes[config.theme].images.IMG_players[player_number]:getHeight()) -- keep image ratio
      menu_drawf(themes[config.theme].images.IMG_players[player_number], render_x+1, render_y+button_height-1, "left", "bottom", 0, scale, scale )
      scale = 0.25*button_width/math.max(themes[config.theme].images.IMG_levels[cursor_data.state.level]:getWidth(),themes[config.theme].images.IMG_levels[cursor_data.state.level]:getHeight()) -- keep image ratio
      menu_drawf(themes[config.theme].images.IMG_levels[cursor_data.state.level], render_x+button_width-1, render_y+button_height-1, "right", "bottom", 0, scale, scale )
    end

    local function draw_panels(cursor_data,player_number,y_padding)
      local panels_max_width = 0.25*button_height
      local panels_width = math.min(panels_max_width,panels[cursor_data.state.panels_dir].images.classic[1][1]:getWidth())
      local padding_x = 0.5*button_width-3*panels_width -- center them, not 3.5 mysteriously?
      if cursor_data.state.level >= 9 then
        padding_x = padding_x-0.5*panels_width
      end
      local is_selected = cursor_data.selected and cursor_data.state.cursor == "__Panels"
      if is_selected then
        padding_x = padding_x-panels_width
      end
      local panels_scale = panels_width/panels[cursor_data.state.panels_dir].images.classic[1][1]:getWidth()
      menu_drawf(themes[config.theme].images.IMG_players[player_number], render_x+padding_x, render_y+y_padding, "center", "center" )
      padding_x = padding_x + panels_width
      if is_selected then
        gprintf("<", render_x+padding_x-0.5*panels_width, render_y+y_padding-0.5*text_height,panels_width,"center")
        padding_x = padding_x + panels_width
      end
      for i=1,8 do
        if i ~= 7 and (i ~= 6 or cursor_data.state.level >= 9) then
          menu_drawf(panels[cursor_data.state.panels_dir].images.classic[i][1], render_x+padding_x, render_y+y_padding, "center", "center", 0, panels_scale, panels_scale )
          padding_x = padding_x + panels_width
        end
      end
      if is_selected then
        gprintf(">", render_x+padding_x-0.5*panels_width, render_y+y_padding-0.5*text_height,panels_width,"center")
      end
    end

    local function draw_levels(cursor_data,player_number,y_padding)
      local level_max_width = 0.2*button_height
      local level_width = math.min(level_max_width,themes[config.theme].images.IMG_levels[1]:getWidth())
      local padding_x = 0.5*button_width-5*level_width
      local is_selected = cursor_data.selected and cursor_data.state.cursor == "__Level"
      if is_selected then
        padding_x = padding_x-level_width
      end
      local level_scale = level_width/themes[config.theme].images.IMG_levels[1]:getWidth()
      menu_drawf(themes[config.theme].images.IMG_players[player_number], render_x+padding_x, render_y+y_padding, "center", "center" )
      padding_x = padding_x + level_width
      if is_selected then
        gprintf("<", render_x+padding_x-0.5*level_width, render_y+y_padding-0.5*text_height,level_width,"center")
        padding_x = padding_x + level_width
      end
      for i=1,#level_to_starting_speed do --which should equal the number of levels in the game
        local use_unfocus = cursor_data.state.level < i
        if use_unfocus then
          menu_drawf(themes[config.theme].images.IMG_levels_unfocus[i], render_x+padding_x, render_y+y_padding, "center", "center", 0, level_scale, level_scale )
        else
          menu_drawf(themes[config.theme].images.IMG_levels[i], render_x+padding_x, render_y+y_padding, "center", "center", 0, level_scale, level_scale )
        end
        if i == cursor_data.state.level then
          menu_drawf(themes[config.theme].images.IMG_level_cursor, render_x+padding_x, render_y+y_padding+themes[config.theme].images.IMG_levels[i]:getHeight()*0.5, "center", "top", 0, level_scale, level_scale )
        end
        padding_x = padding_x + level_width
      end
      if is_selected then
        gprintf(">", render_x+padding_x-0.5*level_width, render_y+y_padding-0.5*text_height,level_width,"center")
      end
    end

    local function draw_match_type(cursor_data,player_number,y_padding)
      local padding_x = math.floor(0.5*button_width - themes[config.theme].images.IMG_players[player_number]:getWidth()*0.5 - 46)  -- ty GIMP; no way to know the size of the text?
      menu_drawf(themes[config.theme].images.IMG_players[player_number], render_x+padding_x, render_y+y_padding, "center", "center" )
      padding_x = padding_x+themes[config.theme].images.IMG_players[player_number]:getWidth()
      local to_print
      if cursor_data.state.ranked then
        to_print = loc("ss_casual").." ["..loc("ss_ranked").."]"
      else
        to_print = "["..loc("ss_casual").."] "..loc("ss_ranked")
      end
      gprint(to_print, render_x+padding_x, render_y+y_padding-0.5*text_height-1)
    end

    local function draw_stage(cursor_data,player_number,x_padding)
      local stage_dimensions = { 80, 45 }
      local y_padding = math.floor(0.5*button_height)
      local padding_x = math.floor(x_padding-0.5*stage_dimensions[1])
      local is_selected = cursor_data.selected and cursor_data.state.cursor == "__Stage"
      if is_selected then
        local arrow_pos = select_screen.character_select_mode == "2p_net_vs"
          and { math.floor(render_x+x_padding-20), math.floor(render_y+y_padding-stage_dimensions[2]*0.5-15) }
          or { math.floor(render_x+padding_x-13), math.floor(render_y+y_padding+0.25*text_height) }
        gprintf("<", arrow_pos[1], arrow_pos[2],10,"center")
      end

      local thumbnail = cursor_data.state.stage_is_random and themes[config.theme].images.IMG_random_stage or stages[cursor_data.state.stage].images.thumbnail
      local scale_x = stage_dimensions[1]/thumbnail:getWidth()
      local scale_y = stage_dimensions[2]/thumbnail:getHeight()

      -- background for thumbnail
      grectangle("line", render_x+padding_x, math.floor(render_y+y_padding-stage_dimensions[2]*0.5), stage_dimensions[1], stage_dimensions[2])
      -- thumbnail
      menu_drawf(thumbnail, render_x+padding_x, render_y+y_padding-1, "left", "center", 0, scale_x, scale_y )
      -- player image
      local player_icon_pos = select_screen.character_select_mode == "2p_net_vs"
        and { math.floor(render_x+padding_x+stage_dimensions[1]*0.5), math.floor(render_y+y_padding-stage_dimensions[2]*0.5-7) }
        or { math.floor(render_x+padding_x-10), math.floor(render_y+y_padding-stage_dimensions[2]*0.25) }
      menu_drawf(themes[config.theme].images.IMG_players[player_number], player_icon_pos[1], player_icon_pos[2], "center", "center" )
      -- display name
      local display_name = cursor_data.state.stage_is_random and loc("random") or stages[cursor_data.state.stage].display_name
      gprintf(display_name, render_x+padding_x, math.floor(render_y+y_padding+stage_dimensions[2]*0.5),stage_dimensions[1],"center",nil,1,small_font)

      padding_x = padding_x+stage_dimensions[1]

      if is_selected then
        local arrow_pos = select_screen.character_select_mode == "2p_net_vs"
          and { math.floor(render_x+x_padding+11), math.floor(render_y+y_padding-stage_dimensions[2]*0.5-15) }
          or { math.floor(render_x+padding_x+3), math.floor(render_y+y_padding+0.25*text_height) }
        gprintf(">", arrow_pos[1], arrow_pos[2], 10,"center")
      end
    end

    local pstr
    if string.sub(str, 1, 2) == "__" then
      pstr = string.sub(str, 3)
    end
    if str == "__Mode" then
      if (select_screen.character_select_mode == "2p_net_vs" or select_screen.character_select_mode == "2p_local_vs") then
        draw_match_type(cursor_data[1],1,0.4*button_height)
        draw_match_type(cursor_data[2],2,0.7*button_height)
      else
        draw_match_type(cursor_data[1],1,0.5*button_height)
      end
    elseif str == "__Panels" then
      if (select_screen.character_select_mode == "2p_net_vs" or select_screen.character_select_mode == "2p_local_vs") then
        draw_panels(cursor_data[1],1,0.4*button_height)
        draw_panels(cursor_data[2],2,0.7*button_height)
      else
        draw_panels(cursor_data[1],1,0.5*button_height)
      end
    elseif str == "__Stage" then
      if (select_screen.character_select_mode == "2p_net_vs" or select_screen.character_select_mode == "2p_local_vs") then
        draw_stage(cursor_data[1],1,0.25*button_width)
        draw_stage(cursor_data[2],2,0.75*button_width)
      else
        draw_stage(cursor_data[1],1,0.5*button_width)
      end
    elseif str == "__Level" then
      if (select_screen.character_select_mode == "2p_net_vs" or select_screen.character_select_mode == "2p_local_vs") then
        draw_levels(cursor_data[1],1,0.4*button_height)
        draw_levels(cursor_data[2],2,0.7*button_height)
      else
        draw_levels(cursor_data[1],1,0.5*button_height)
      end
    elseif str == "P1" then
      draw_player_state(cursor_data[1],1)
      pstr = my_name
    elseif str == "P2" then
      draw_player_state(cursor_data[2],2)
      pstr = op_name
    elseif character then
      pstr = character.display_name
    elseif string.sub(str, 1, 2) ~= "__" then
      pstr = str:gsub("^%l", string.upper)
    end
    if x ~= 0 then
      if cursor_data[1].state and cursor_data[1].state.cursor == str 
        and ( (str ~= "__Empty" and str ~= "__Reserved") or ( cursor_data[1].position[1] == x and cursor_data[1].position[2] == y ) ) then
        draw_cursor(button_height, spacing, 1, cursor_data[1].state.ready)
        if cursor_data[1].can_super_select then
          draw_super_select(1)
        end
      end
      if (select_screen.character_select_mode == "2p_net_vs" or select_screen.character_select_mode == "2p_local_vs")
        and cursor_data[2].state and cursor_data[2].state.cursor == str
        and ( (str ~= "__Empty" and str ~= "__Reserved") or ( cursor_data[2].position[1] == x and cursor_data[2].position[2] == y ) ) then
        draw_cursor(button_height, spacing, 2, cursor_data[2].state.ready)
        if cursor_data[2].can_super_select then
          draw_super_select(2)
        end
      end
    end
    if str ~= "__Empty" and str ~= "__Reserved" then
      local loc_str = {Level= loc("level"), Mode=loc("mode"), Stage=loc("stage"), Panels=loc("panels"), Ready=loc("ready"), Random=loc("random"), Leave=loc("leave")}
      local to_p = loc_str[pstr]
      gprintf( not to_p and pstr or to_p, render_x+x_add, render_y+y_add,width_for_alignment,halign)
    end
  end

  print("got to LOC before net_vs_room character select loop")
  menu_clock = 0

  local v_align_center = { __Ready=true, __Random=true, __Leave=true }
  local is_special_value = { __Leave=true, __Level=true, __Panels=true, __Ready=true, __Stage=true, __Mode=true, __Random=true }

  while true do
    -- draw the buttons, handle horizontal spans
    for i=1,X do
      for j=1,Y do
        local value = map[current_page][i][j]
        local span_width = 1
        if is_special_value[value] then
          if j == 1 or map[current_page][i][j-1] ~= value then
            -- detect how many blocks the special value spans
            if j ~= Y then
              for u=j+1,Y do
                if map[current_page][i][u] == value then
                  span_width = span_width + 1
                else
                  break
                end
              end
            end
          else
            -- has already been drawn 
            span_width = 0
          end
        end

        if span_width ~= 0 then
          draw_button(i,j,span_width,1,value,"center", v_align_center[value] and "center" or "top" )
        end
      end
    end

    if select_screen.character_select_mode == "2p_net_vs" then
      local messages = server_queue:pop_all_with("win_counts", "menu_state", "ranked_match_approved", "leave_room", "match_start", "ranked_match_denied")
      if global_initialize_room_msg then
        messages[#messages+1] = global_initialize_room_msg
        global_initialize_room_msg = nil
      end
      for _,msg in ipairs(messages) do
        if msg.win_counts then
          update_win_counts(msg.win_counts)
        end
        if msg.menu_state then
          if currently_spectating then
            if msg.player_number == 1 or msg.player_number == 2 then
              cursor_data[msg.player_number].state = msg.menu_state
              refresh_based_on_own_mods(cursor_data[msg.player_number].state)
              character_loader_load(cursor_data[msg.player_number].state.character)
              stage_loader_load(cursor_data[msg.player_number].state.stage)
            end
          else
            cursor_data[2].state = msg.menu_state
            refresh_based_on_own_mods(cursor_data[2].state)
            character_loader_load(cursor_data[2].state.character)
            stage_loader_load(cursor_data[2].state.stage)
          end
          refresh_loaded_and_ready(cursor_data[1],cursor_data[2])
        end
        if msg.ranked_match_approved then
          match_type = "Ranked"
          match_type_message = ""
          if msg.caveats then
            match_type_message = match_type_message..(msg.caveats[1] or "")
          end
        elseif msg.ranked_match_denied then
          match_type = "Casual"
          match_type_message = (loc("ss_not_ranked") or "").."  "
          if msg.reasons then
            match_type_message = match_type_message..(msg.reasons[1] or loc("ss_err_no_reason"))
          end
        end
        if msg.leave_room then
          my_win_count = 0
          op_win_count = 0
          return main_dumb_transition, {main_net_vs_lobby, "", 0, 0}
        end
        if msg.match_start or replay_of_match_so_far then
          print("currently_spectating: "..tostring(currently_spectating))
          local fake_P1 = P1
          local fake_P2 = P2
          refresh_based_on_own_mods(msg.opponent_settings)
          refresh_based_on_own_mods(msg.player_settings, true)
          refresh_based_on_own_mods(msg) -- for stage only, other data are meaningless to us
          -- mainly for spectator mode, those characters have already been loaded otherwise
          character_loader_load(msg.player_settings.character)
          character_loader_load(msg.opponent_settings.character)
          current_stage = msg.stage
          stage_loader_load(msg.stage)
          character_loader_wait()
          stage_loader_wait()
          P1 = Stack(1, "vs", msg.player_settings.panels_dir, msg.player_settings.level, msg.player_settings.character, msg.player_settings.player_number)
          P1.cur_wait_time = default_input_repeat_delay  -- this enforces default cur_wait_time for online games.  It is yet to be decided if we want to allow this to be custom online.
          P1.enable_analytics = not currently_spectating and not replay_of_match_so_far
          P2 = Stack(2, "vs", msg.opponent_settings.panels_dir, msg.opponent_settings.level, msg.opponent_settings.character, msg.opponent_settings.player_number)
          P2.cur_wait_time = default_input_repeat_delay  -- this enforces default cur_wait_time for online games.  It is yet to be decided if we want to allow this to be custom online.
          if currently_spectating then
            P1.panel_buffer = fake_P1.panel_buffer
            P1.gpanel_buffer = fake_P1.gpanel_buffer
          end
          P2.panel_buffer = fake_P2.panel_buffer
          P2.gpanel_buffer = fake_P2.gpanel_buffer
          P1.garbage_target = P2
          P2.garbage_target = P1
          move_stack(P2,2)
          replay.vs = {P="",O="",I="",Q="",R="",in_buf="",
                      P1_level=P1.level,P2_level=P2.level,
                      P1_name=my_name, P2_name=op_name,
                      P1_char=P1.character,P2_char=P2.character,
                      P1_cur_wait_time=P1.cur_wait_time, P2_cur_wait_time=P2.cur_wait_time,
                      ranked=msg.ranked, do_countdown=true}
          if currently_spectating and replay_of_match_so_far then --we joined a match in progress
            replay.vs = replay_of_match_so_far.vs
            P1.input_buffer = replay_of_match_so_far.vs.in_buf
            P1.panel_buffer = replay_of_match_so_far.vs.P
            P1.gpanel_buffer = replay_of_match_so_far.vs.Q
            P2.input_buffer = replay_of_match_so_far.vs.I
            P2.panel_buffer = replay_of_match_so_far.vs.O
            P2.gpanel_buffer = replay_of_match_so_far.vs.R
            if replay.vs.ranked then
              match_type = "Ranked"
              match_type_message = ""
            else
              match_type = "Casual"
            end
            replay_of_match_so_far = nil
            P1.play_to_end = true  --this makes foreign_run run until caught up
            P2.play_to_end = true
          end
          if not currently_spectating then
              ask_for_gpanels("000000")
              ask_for_panels("000000")
          end
          to_print = loc("pl_game_start").."\n"..loc("level")..": "..P1.level.."\n"..loc("opponent_level")..": "..P2.level
          if P1.play_to_end or P2.play_to_end then
            to_print = loc("pl_spectate_join")
          end
          for i=1,30 do
            gprint(to_print,unpack(main_menu_screen_pos))
            if not do_messages() then
              return main_dumb_transition, {main_select_mode, loc("ss_disconnect").."\n\n"..loc("ss_return"), 60, 300}
            end
            wait()
          end
          local game_start_timeout = 0
          while P1.panel_buffer == "" or P2.panel_buffer == ""
            or P1.gpanel_buffer == "" or P2.gpanel_buffer == "" do
            --testing getting stuck here at "Game is starting"
            game_start_timeout = game_start_timeout + 1
            print("game_start_timeout = "..game_start_timeout)
            print("P1.panel_buffer = "..P1.panel_buffer)
            print("P2.panel_buffer = "..P2.panel_buffer)
            print("P1.gpanel_buffer = "..P1.gpanel_buffer)
            print("P2.gpanel_buffer = "..P2.gpanel_buffer)
            gprint(to_print,unpack(main_menu_screen_pos))
            if not do_messages() then
              return main_dumb_transition, {main_select_mode, loc("ss_disconnect").."\n\n"..loc("ss_return"), 60, 300}
            end
            wait()
            if game_start_timeout > 250 then
              return main_dumb_transition, {main_select_mode,
                              loc("pl_time_out").."\n"
                              .."\n".."msg.match_start = "..(tostring(msg.match_start) or "nil")
                              .."\n".."replay_of_match_so_far = "..(tostring(replay_of_match_so_far) or "nil")
                              .."\n".."P1.panel_buffer = "..P1.panel_buffer
                              .."\n".."P2.panel_buffer = "..P2.panel_buffer
                              .."\n".."P1.gpanel_buffer = "..P1.gpanel_buffer
                              .."\n".."P2.gpanel_buffer = "..P2.gpanel_buffer,
                              180}
            end
          love.timer.sleep(0.017)
          end
          P1:starting_state()
          P2:starting_state()
          return main_dumb_transition, {main_net_vs, "", 0, 0}
        end
      end
    end

    local my_rating_difference = ""
    local op_rating_difference = ""
    if current_server_supports_ranking and not global_current_room_ratings[my_player_number].placement_match_progress then
      if global_current_room_ratings[my_player_number].difference then
        if global_current_room_ratings[my_player_number].difference>= 0 then
          my_rating_difference = "(+"..global_current_room_ratings[my_player_number].difference..") "
        else
          my_rating_difference = "("..global_current_room_ratings[my_player_number].difference..") "
        end
      end
      if global_current_room_ratings[op_player_number].difference then
        if global_current_room_ratings[op_player_number].difference >= 0 then
          op_rating_difference = "(+"..global_current_room_ratings[op_player_number].difference..") "
        else
          op_rating_difference = "("..global_current_room_ratings[op_player_number].difference..") "
        end
      end
    end
    local function get_player_state_str(player_number, rating_difference, win_count, op_win_count, expected_win_ratio)
      local state = ""
      if current_server_supports_ranking then
        state = state..loc("ss_rating").." "..(global_current_room_ratings[player_number].league or "")
        if not global_current_room_ratings[player_number].placement_match_progress then
          state = state.."\n"..rating_difference..global_current_room_ratings[player_number].new
        elseif global_current_room_ratings[player_number].placement_match_progress
        and global_current_room_ratings[player_number].new
        and global_current_room_ratings[player_number].new == 0 then
          state = state.."\n"..global_current_room_ratings[player_number].placement_match_progress
        end
      end
      if select_screen.character_select_mode == "2p_net_vs" or select_screen.character_select_mode == "2p_local_vs" then
        if current_server_supports_ranking then
          state = state.."\n"
        end
        state = state..loc("ss_wins").." "..win_count
        if (current_server_supports_ranking and expected_win_ratio) or win_count + op_win_count > 0 then
          state = state.."\n"..loc("ss_winrate").."\n"
          local need_line_return = false
          if win_count + op_win_count > 0 then
            state = state.."    "..loc("ss_current_rating").." "..(100*round(win_count/(op_win_count+win_count),2)).."%"
            need_line_return = true
          end
          if current_server_supports_ranking and expected_win_ratio then
            if need_line_return then
              state = state.."\n"
            end
            state = state.."    "..loc("ss_expected_rating").." "..expected_win_ratio.."%"
          end
        end
      end
      return state
    end
    draw_button(0,1,1,1,"P1")
    draw_button(0,2,2,1,get_player_state_str(my_player_number,my_rating_difference,my_win_count,op_win_count,my_expected_win_ratio),"left","top",true)
    if cursor_data[1].state and op_name then
      draw_button(0,7,1,1,"P2")
      draw_button(0,8,2,1,get_player_state_str(op_player_number,op_rating_difference,op_win_count,my_win_count,op_expected_win_ratio),"left","top",true)
      --state = state.." "..json.encode(op_state)
    end
    if select_screen.character_select_mode == "2p_net_vs" then
      if not cursor_data[1].state.ranked and not cursor_data[2].state.ranked then
        match_type_message = ""
      end
      local match_type_str = ""
      if match_type == "Casual" then
        match_type_str = loc("ss_casual")
      elseif match_type == "Ranked" then
        match_type_str = loc("ss_ranked")
      end
      gprintf(match_type_str, 0, 15, canvas_width, "center")
      gprintf(match_type_message, 0, 30, canvas_width, "center")
    end
    if pages_amount ~= 1 then
      gprintf(loc("page").." "..current_page.."/"..pages_amount, 0, 660, canvas_width, "center")
    end
    wait()

    local ret = nil

    local function move_cursor(cursor,direction)
      local cursor_pos = cursor.position
      local dx,dy = unpack(direction)
      local can_x,can_y = wrap(1, cursor_pos[1]+dx, X), wrap(1, cursor_pos[2]+dy, Y)
      while can_x ~= cursor_pos[1] or can_y ~= cursor_pos[2] do
        if map[current_page][can_x][can_y] and ( map[current_page][can_x][can_y] ~= map[current_page][cursor_pos[1]][cursor_pos[2]] or 
          map[current_page][can_x][can_y] == "__Empty" or map[current_page][can_x][can_y] == "__Reserved" ) then
          break
        end
        can_x,can_y = wrap(1, can_x+dx, X), wrap(1, can_y+dy, Y)
      end
      cursor_pos[1],cursor_pos[2] = can_x,can_y
      local character = characters[map[current_page][can_x][can_y]]
      cursor.can_super_select = character and ( character.stage or character.panels )
    end

    local function change_panels_dir(panels_dir,increment)
      local current = 0
      for k,v in ipairs(panels_ids) do
        if v == panels_dir then
          current = k
          break
        end
      end
      local dir_count = #panels_ids
      local new_theme_idx = ((current - 1 + increment) % dir_count) + 1
      for k,v in ipairs(panels_ids) do
        if k == new_theme_idx then
            return v
        end
      end
      return panels_dir
    end

    local function change_stage(state,increment)
      -- random_stage_special_value is placed at the end and is 'replaced' by a random pick and stage_is_random=true
      local current = nil
      for k,v in ipairs(stages_ids_for_current_theme) do
        if v == state.stage then
          current = k
          break
        end
      end
      if state.stage == random_stage_special_value or state.stage_is_random then
        current = #stages_ids_for_current_theme+1
      end
      if current == nil then -- stage belonged to another set of stages, it's no more in the list
        current = 0
      end
      local dir_count = #stages_ids_for_current_theme + 1
      local new_stage_idx = ((current - 1 + increment) % dir_count) + 1
      if new_stage_idx <= #stages_ids_for_current_theme then
        state.stage_is_random = false
        state.stage = stages_ids_for_current_theme[new_stage_idx]
      else
        state.stage_is_random = true
        state.stage = uniformly(stages_ids_for_current_theme)
      end
    end

    local function on_quit()
      if themes[config.theme].musics.select_screen then
        stop_the_music()
      end
      if select_screen.character_select_mode == "2p_net_vs" then
        if not do_leave() then
          ret = {main_dumb_transition, {main_select_mode, loc("ss_error_leave"), 60, 300}}
        end
      else
        ret = {main_select_mode}
      end
    end 

    local function on_select(cursor,super)
      local selectable = {__Stage=true, __Panels=true, __Level=true, __Ready=true}
      if selectable[cursor.state.cursor] then
        if cursor.selected and cursor.state.cursor == "__Stage" then
          -- load stage even if hidden!
          stage_loader_load(cursor.state.stage)
        end
        cursor.selected = not cursor.selected
      elseif cursor.state.cursor == "__Leave" then
        on_quit()
      elseif cursor.state.cursor == "__Random" then
        cursor.state.character_is_random = true
        cursor.state.character = uniformly(characters_ids_for_current_theme)
        cursor.state.character_display_name = characters[cursor.state.character].display_name
        character_loader_load(cursor.state.character)
        cursor.state.cursor = "__Ready"
        cursor.position = shallowcpy(name_to_xy_per_page[current_page]["__Ready"])
        cursor.can_super_select = false
      elseif cursor.state.cursor == "__Mode" then
        cursor.state.ranked = not cursor.state.ranked
      elseif ( cursor.state.cursor ~= "__Empty" and cursor.state.cursor ~= "__Reserved" ) then
        cursor.state.character_is_random = false
        cursor.state.character = cursor.state.cursor
        cursor.state.character_display_name = characters[cursor.state.character].display_name
        local character = characters[cursor.state.character]
        character:play_selection_sfx()
        character_loader_load(cursor.state.character)
        if super then
          if character.stage then
            cursor.state.stage = character.stage
            stage_loader_load(cursor.state.stage)
            cursor.state.stage_is_random = false
          end
          if character.panels then
            cursor.state.panels_dir = character.panels
          end
        end
        --When we select a character, move cursor to "__Ready"
        cursor.state.cursor = "__Ready"
        cursor.position = shallowcpy(name_to_xy_per_page[current_page]["__Ready"])
        cursor.can_super_select = false
      end
    end

    variable_step(function()
      menu_clock = menu_clock + 1

      character_loader_update()
      stage_loader_update()
      refresh_loaded_and_ready(cursor_data[1].state,cursor_data[2] and cursor_data[2].state or nil)

      local up,down,left,right = {-1,0}, {1,0}, {0,-1}, {0,1}
      if not currently_spectating then
        local KMax = 1
        if select_screen.character_select_mode == "2p_local_vs" then
          KMax = 2
        end
        for i=1,KMax do
          local k=K[i]
          local cursor = cursor_data[i]
          if menu_prev_page(k) then
            if not cursor.selected then current_page = bound(1, current_page-1, pages_amount) end
          elseif menu_next_page(k) then
            if not cursor.selected then current_page = bound(1, current_page+1, pages_amount) end
          elseif menu_up(k) then
            if not cursor.selected then move_cursor(cursor,up) end
          elseif menu_down(k) then
            if not cursor.selected then move_cursor(cursor,down) end
          elseif menu_left(k) then
            if cursor.selected then
              if cursor.state.cursor == "__Level" then
                cursor.state.level = bound(1, cursor.state.level-1, #level_to_starting_speed) --which should equal the number of levels in the game
              elseif cursor.state.cursor == "__Panels" then
                cursor.state.panels_dir = change_panels_dir(cursor.state.panels_dir,-1)
              elseif cursor.state.cursor == "__Stage" then
                change_stage(cursor.state,-1)
              end
            end
            if not cursor.selected then move_cursor(cursor,left) end
          elseif menu_right(k) then
            if cursor.selected then
              if cursor.state.cursor == "__Level" then
                cursor.state.level = bound(1, cursor.state.level+1, #level_to_starting_speed) --which should equal the number of levels in the game
              elseif cursor.state.cursor == "__Panels" then
                cursor.state.panels_dir = change_panels_dir(cursor.state.panels_dir,1)
              elseif cursor.state.cursor == "__Stage" then
                change_stage(cursor.state,1)
              end
            end
            if not cursor.selected then move_cursor(cursor,right) end
          elseif menu_long_enter(k) then
            on_select(cursor, true)
          elseif menu_enter(k) and (not cursor.can_super_select or menu_pressing_enter(k) < super_selection_enable_ratio) then
            on_select(cursor, false)
          elseif menu_escape(k) then
            if cursor.state.cursor == "__Leave" then
              on_quit()
            end
            cursor.selected = false
            cursor.position = shallowcpy(name_to_xy_per_page[current_page]["__Leave"])
            cursor.can_super_select = false
          end
          if cursor.state ~= nil then
            cursor.state.cursor = map[current_page][cursor.position[1]][cursor.position[2]]
            cursor.state.wants_ready = cursor.selected and cursor.state.cursor=="__Ready"
          end
        end
        -- update config, does not redefine it
        config.character = cursor_data[1].state.character_is_random and random_character_special_value or cursor_data[1].state.character
        config.stage = cursor_data[1].state.stage_is_random and random_stage_special_value or cursor_data[1].state.stage
        config.level = cursor_data[1].state.level
        config.ranked = cursor_data[1].state.ranked
        config.panels = cursor_data[1].state.panels_dir

        if select_screen.character_select_mode == "2p_local_vs" then -- this is registered for future entering of the lobby
          global_op_state = shallowcpy(cursor_data[2].state)
          global_op_state.stage = global_op_state.stage_is_random and random_stage_special_value or global_op_state.stage
          global_op_state.wants_ready = false
        end

        if select_screen.character_select_mode == "2p_net_vs" and not content_equal(cursor_data[1].state, prev_state) and not currently_spectating then
          json_send({menu_state=cursor_data[1].state})
        end
        prev_state = shallowcpy(cursor_data[1].state)

      else -- (we are spectating)
        if menu_escape(K[1]) then
          do_leave()
          ret = {main_net_vs_lobby}
        end
      end
    end)
    if ret then
      return unpack(ret)
    end
    if cursor_data[1].state.ready and select_screen.character_select_mode == "1p_vs_yourself" then
      P1 = Stack(1, "vs", cursor_data[1].state.panels_dir, cursor_data[1].state.level, cursor_data[1].state.character)
      P1.enable_analytics = true
      P1.garbage_target = P1
      make_local_panels(P1, "000000")
      make_local_gpanels(P1, "000000")
      current_stage = cursor_data[1].state.stage
      stage_loader_load(current_stage)
      stage_loader_wait()
      P1:starting_state()
      return main_dumb_transition, {main_local_vs_yourself, "", 0, 0}
    elseif cursor_data[1].state.ready and select_screen.character_select_mode == "2p_local_vs" and cursor_data[2].state.ready then
      P1 = Stack(1, "vs", cursor_data[1].state.panels_dir, cursor_data[1].state.level, cursor_data[1].state.character)
      P1.enable_analytics = true
      P2 = Stack(2, "vs", cursor_data[2].state.panels_dir, cursor_data[2].state.level, cursor_data[2].state.character)
      P1.garbage_target = P2
      P2.garbage_target = P1
      current_stage = cursor_data[math.random(1,2)].state.stage
      stage_loader_load(current_stage)
      stage_loader_wait()
      move_stack(P2,2)
      -- TODO: this does not correctly implement starting configurations.
      -- Starting configurations should be identical for visible blocks, and
      -- they should not be completely flat.
      --
      -- In general the block-generation logic should be the same as the server's, so
      -- maybe there should be only one implementation.
      make_local_panels(P1, "000000")
      make_local_gpanels(P1, "000000")
      make_local_panels(P2, "000000")
      make_local_gpanels(P2, "000000")
      P1:starting_state()
      P2:starting_state()
      return main_dumb_transition, {main_local_vs, "", 0, 0}
    elseif select_screen.character_select_mode == "2p_net_vs" then
      if not do_messages() then
        return main_dumb_transition, {main_select_mode, loc("ss_disconnect").."\n\n"..loc("ss_return"), 60, 300}
      end
    end
  end
end

return select_screen