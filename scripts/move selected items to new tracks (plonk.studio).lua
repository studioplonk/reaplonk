-- @description Move selected items to new tracks (plonk.studio)
-- @version 0.1
-- @author Till Bovermann
-- @link https://plonk.studio
-- @about
--   Moves each selected media item to a new track, copies FX from the original track, and removes the original track if empty.
-- @changelog
--    + 2026-10-14 -- bug fixes, generalisation to also work on tracks if no items are selected


reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)

local items = {}

-- 1. Gather target items (if no items are selected, gather items from selected tracks)
local num_selected_items = reaper.CountSelectedMediaItems(0)

if num_selected_items > 0 then
    for i = 0, num_selected_items - 1 do
        table.insert(items, reaper.GetSelectedMediaItem(0, i))
    end
else
    local num_selected_tracks = reaper.CountSelectedTracks(0)
    if num_selected_tracks > 0 then
        for t = 0, num_selected_tracks - 1 do
            local track = reaper.GetSelectedTrack(0, t)
            local item_count = reaper.CountTrackMediaItems(track)
            for i = 0, item_count - 1 do
                table.insert(items, reaper.GetTrackMediaItem(track, i))
            end
        end
    end
end

if #items == 0 then
    reaper.PreventUIRefresh(-1)
    return
end

-- Set to store original tracks to check for cleanup later
local original_tracks_set = {}
local original_tracks_list = {}

-- 2. Process gathered items
for i, item in ipairs(items) do
    if item then
        local original_track = reaper.GetMediaItem_Track(item)
        if original_track and not original_tracks_set[original_track] then
            original_tracks_set[original_track] = true
            table.insert(original_tracks_list, original_track)
        end

        local take = reaper.GetActiveTake(item)
        local item_name = take and reaper.GetTakeName(take) or ("Item_" .. i)

        -- Create new track at the end
        reaper.InsertTrackAtIndex(reaper.CountTracks(0), true)
        local new_track = reaper.GetTrack(0, reaper.CountTracks(0) - 1)
        reaper.GetSetMediaTrackInfo_String(new_track, "P_NAME", item_name, true)

        -- Copy FX from item's original track
        if original_track then
            local num_fx = reaper.TrackFX_GetCount(original_track)
            for fx = 0, num_fx - 1 do
                reaper.TrackFX_CopyToTrack(original_track, fx, new_track, fx, false)
            end
        end

        -- Move item to new track
        reaper.MoveMediaItemToTrack(item, new_track)

        -- -- Create region
        -- local item_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
        -- local item_end = item_start + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
        -- reaper.AddProjectMarker2(0, true, item_start, item_end, item_name, -1, 0)
    end
end

-- 3. Delete original tracks if they are now empty
for _, orig_track in ipairs(original_tracks_list) do
    if reaper.CountTrackMediaItems(orig_track) == 0 then
        reaper.DeleteTrack(orig_track)
    end
end

reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()
reaper.Undo_EndBlock("Move items to new tracks, copy FX, and remove original track", -1)
