-- @description Explode channels into new tracks (plonk.studio)
-- @version 0.1
-- @author Till Bovermann
-- @link https://plonk.studio
-- @about
--   Explodes multichannel items into separate tracks based on their active channels.
-- @changelog
--    + 2026-10-14 -- bug fixes, generalisation to also work on tracks if no items are selected

reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)

-- Helper to determine visible channels based on take Channel Mode (I_CHANMODE)
local function get_active_channels(take, src)
    local num_channels = reaper.GetMediaSourceNumChannels(src)
    local chanmode = math.floor(reaper.GetMediaItemTakeInfo_Value(take, "I_CHANMODE"))
    local active = {}

    if chanmode == 0 then
        -- Normal mode: all source channels visible
        for ch = 0, num_channels - 1 do
            table.insert(active, {
                ch_index = ch,
                chanmode = 3 + ch
            })
        end
    elseif chanmode == 1 then
        -- Reverse stereo mode: channels 0 and 1
        local max_ch = math.min(2, num_channels)
        for ch = 0, max_ch - 1 do
            table.insert(active, {
                ch_index = ch,
                chanmode = 3 + ch
            })
        end
    elseif chanmode == 2 then
        -- Downmix to mono
        table.insert(active, {
            ch_index = 0,
            chanmode = 2
        })
    elseif chanmode >= 3 and chanmode <= 66 then
        -- Mono channel mode (3 = ch 0, 4 = ch 1, etc.)
        local ch = chanmode - 3
        if ch < num_channels then
            table.insert(active, {
                ch_index = ch,
                chanmode = chanmode
            })
        end
    elseif chanmode >= 67 and chanmode <= 130 then
        -- Stereo pair mode (67 = ch 0 & 1, 68 = ch 1 & 2, etc.)
        local ch1 = chanmode - 67
        local ch2 = ch1 + 1
        if ch1 < num_channels then
            table.insert(active, {
                ch_index = ch1,
                chanmode = 3 + ch1
            })
        end
        if ch2 < num_channels then
            table.insert(active, {
                ch_index = ch2,
                chanmode = 3 + ch2
            })
        end
    else
        -- Fallback: treat as normal mode
        for ch = 0, num_channels - 1 do
            table.insert(active, {
                ch_index = ch,
                chanmode = 3 + ch
            })
        end
    end

    return active
end

local function explode_multichannel_items()
    local target_items = {}
    local num_selected = reaper.CountSelectedMediaItems(0)

    if num_selected > 0 then
        for i = 0, num_selected - 1 do
            table.insert(target_items, reaper.GetSelectedMediaItem(0, i))
        end
    else
        local num_selected_tracks = reaper.CountSelectedTracks(0)
        if num_selected_tracks > 0 then
            for t = 0, num_selected_tracks - 1 do
                local track = reaper.GetSelectedTrack(0, t)
                local item_count = reaper.CountTrackMediaItems(track)
                for i = 0, item_count - 1 do
                    table.insert(target_items, reaper.GetTrackMediaItem(track, i))
                end
            end
        end
    end

    if #target_items == 0 then
        reaper.ShowMessageBox("No selected items or items on selected tracks.", "Error", 0)
        return
    end

    -- Gather target items and group by track
    local tracks_map = {}
    local tracks_order = {}

    for _, item in ipairs(target_items) do
        if item then
            local take = reaper.GetActiveTake(item)
            if take then
                local track = reaper.GetMediaItem_Track(item)
                if not tracks_map[track] then
                    tracks_map[track] = {
                        track = track,
                        items = {},
                        max_visible_count = 0
                    }
                    table.insert(tracks_order, track)
                end

                local src = reaper.GetMediaItemTake_Source(take)
                if src then
                    local active_channels = get_active_channels(take, src)
                    if #active_channels > 0 then
                        table.insert(tracks_map[track].items, {
                            item = item,
                            take = take,
                            src = src,
                            active_channels = active_channels
                        })
                        if #active_channels > tracks_map[track].max_visible_count then
                            tracks_map[track].max_visible_count = #active_channels
                        end
                    end
                end
            end
        end
    end

    -- Process each track with selected items
    for _, track in ipairs(tracks_order) do
        local track_data = tracks_map[track]
        local items_info = track_data.items
        local max_visible_count = track_data.max_visible_count

        if max_visible_count > 0 and #items_info > 0 then
            local original_track = track
            local original_track_index = math.floor(reaper.GetMediaTrackInfo_Value(original_track, "IP_TRACKNUMBER")) - 1

            local new_tracks = {}

            for idx = 1, max_visible_count do
                -- Create new track for each available channel slot
                reaper.InsertTrackAtIndex(original_track_index + idx, true)
                local new_track = reaper.GetTrack(0, original_track_index + idx)
                table.insert(new_tracks, new_track)

                -- Rename track to indicate channel number (1-based)
                reaper.GetSetMediaTrackInfo_String(new_track, "P_NAME", "Ch " .. idx, true)
            end

            -- Safely update folder depth hierarchy
            local orig_depth = reaper.GetMediaTrackInfo_Value(original_track, "I_FOLDERDEPTH")
            if orig_depth <= 0 then
                reaper.SetMediaTrackInfo_Value(original_track, "I_FOLDERDEPTH", 1)
                for idx, new_tr in ipairs(new_tracks) do
                    if idx == #new_tracks then
                        reaper.SetMediaTrackInfo_Value(new_tr, "I_FOLDERDEPTH", orig_depth - 1)
                    else
                        reaper.SetMediaTrackInfo_Value(new_tr, "I_FOLDERDEPTH", 0)
                    end
                end
            else
                for _, new_tr in ipairs(new_tracks) do
                    reaper.SetMediaTrackInfo_Value(new_tr, "I_FOLDERDEPTH", 0)
                end
            end

            -- Explode items on this track onto the new channel tracks
            for _, item_data in ipairs(items_info) do
                local item = item_data.item
                local take = item_data.take
                local src = item_data.src
                local active_channels = item_data.active_channels

                -- Read Media Item properties
                local position = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
                local length = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
                local item_vol = reaper.GetMediaItemInfo_Value(item, "D_VOL")
                local snapoffs = reaper.GetMediaItemInfo_Value(item, "D_SNAPOFFSET")
                local fadein = reaper.GetMediaItemInfo_Value(item, "D_FADEINLEN")
                local fadeout = reaper.GetMediaItemInfo_Value(item, "D_FADEOUTLEN")
                local fadein_dir = reaper.GetMediaItemInfo_Value(item, "D_FADEINLEN_AUTO")
                local fadeout_dir = reaper.GetMediaItemInfo_Value(item, "D_FADEOUTLEN_AUTO")
                local fadein_shape = reaper.GetMediaItemInfo_Value(item, "C_FADEINSHAPE")
                local fadeout_shape = reaper.GetMediaItemInfo_Value(item, "C_FADEOUTSHAPE")
                local mute = reaper.GetMediaItemInfo_Value(item, "B_MUTE")
                local color = reaper.GetMediaItemInfo_Value(item, "I_CUSTOMCOLOR")
                local loop_src = reaper.GetMediaItemInfo_Value(item, "B_LOOPSRC")
                local lock = reaper.GetMediaItemInfo_Value(item, "C_LOCK")

                -- Read Media Take properties
                local take_vol = reaper.GetMediaItemTakeInfo_Value(take, "D_VOL")
                local take_pan = reaper.GetMediaItemTakeInfo_Value(take, "D_PAN")
                local take_panmode = reaper.GetMediaItemTakeInfo_Value(take, "I_PANMODE")
                local take_offs = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
                local take_rate = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
                local take_pitch = reaper.GetMediaItemTakeInfo_Value(take, "D_PITCH")
                local take_pitchmode = reaper.GetMediaItemTakeInfo_Value(take, "I_PITCHMODE")
                local take_ppmode = reaper.GetMediaItemTakeInfo_Value(take, "C_PITCHMODE")
                local preserve_pitch = reaper.GetMediaItemTakeInfo_Value(take, "B_PPITCH")
                local _, take_name = reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)

                for v_idx, ch_info in ipairs(active_channels) do
                    local target_track = new_tracks[v_idx]
                    if target_track then
                        local new_item = reaper.AddMediaItemToTrack(target_track)
                        reaper.SetMediaItemInfo_Value(new_item, "D_POSITION", position)
                        reaper.SetMediaItemInfo_Value(new_item, "D_LENGTH", length)
                        reaper.SetMediaItemInfo_Value(new_item, "D_VOL", item_vol)
                        reaper.SetMediaItemInfo_Value(new_item, "D_SNAPOFFSET", snapoffs)
                        reaper.SetMediaItemInfo_Value(new_item, "D_FADEINLEN", fadein)
                        reaper.SetMediaItemInfo_Value(new_item, "D_FADEOUTLEN", fadeout)
                        reaper.SetMediaItemInfo_Value(new_item, "D_FADEINLEN_AUTO", fadein_dir)
                        reaper.SetMediaItemInfo_Value(new_item, "D_FADEOUTLEN_AUTO", fadeout_dir)
                        reaper.SetMediaItemInfo_Value(new_item, "C_FADEINSHAPE", fadein_shape)
                        reaper.SetMediaItemInfo_Value(new_item, "C_FADEOUTSHAPE", fadeout_shape)
                        reaper.SetMediaItemInfo_Value(new_item, "B_MUTE", mute)
                        reaper.SetMediaItemInfo_Value(new_item, "I_CUSTOMCOLOR", color)
                        reaper.SetMediaItemInfo_Value(new_item, "B_LOOPSRC", loop_src)
                        reaper.SetMediaItemInfo_Value(new_item, "C_LOCK", lock)

                        local new_take = reaper.AddTakeToMediaItem(new_item)
                        reaper.SetMediaItemTake_Source(new_take, src)
                        reaper.SetMediaItemTakeInfo_Value(new_take, "I_CHANMODE", ch_info.chanmode)
                        reaper.SetMediaItemTakeInfo_Value(new_take, "D_VOL", take_vol)
                        reaper.SetMediaItemTakeInfo_Value(new_take, "D_PAN", take_pan)
                        reaper.SetMediaItemTakeInfo_Value(new_take, "I_PANMODE", take_panmode)
                        reaper.SetMediaItemTakeInfo_Value(new_take, "D_STARTOFFS", take_offs)
                        reaper.SetMediaItemTakeInfo_Value(new_take, "D_PLAYRATE", take_rate)
                        reaper.SetMediaItemTakeInfo_Value(new_take, "D_PITCH", take_pitch)
                        reaper.SetMediaItemTakeInfo_Value(new_take, "I_PITCHMODE", take_pitchmode)
                        reaper.SetMediaItemTakeInfo_Value(new_take, "C_PITCHMODE", take_ppmode)
                        reaper.SetMediaItemTakeInfo_Value(new_take, "B_PPITCH", preserve_pitch)

                        if take_name and take_name ~= "" then
                            reaper.GetSetMediaItemTakeInfo_String(new_take, "P_NAME", take_name, true)
                        end
                    end
                end

                -- Delete original item
                reaper.DeleteTrackMediaItem(original_track, item)
            end
        end
    end

    -- Clear item selection (Option 4B)
    reaper.SelectAllMediaItems(0, false)

    reaper.UpdateArrange()
end

explode_multichannel_items()

reaper.PreventUIRefresh(-1)
reaper.Undo_EndBlock("Explode Multichannel Audio to Separate One-Channel Items on New Grouped Tracks", -1)
