local Coverage = {}

local FINDINGS = {
    ["P0-01 occupied-slot overwrite"] = { "title_keyboard_overwrite_cancel_preserves_bytes" },
    ["P0-02 wrapper exit lifecycle"] = { "wrapper_keyboard_middle_exit_keeps_cycle_running", "wrapper_mouse_final_frame_finishes_once" },
    ["P0-03 persistent defaults"] = { "domain_save_exact_defaults", "save_v2_migration" },
    ["P0-04 pallet ownership"] = { "domain_pallet_rejects_jack_to_cutter_claim" },
    ["P1-01 completion and payment"] = { "full_loop_pickup_archives_and_pays", "full_loop_payment_cannot_repeat" },
    ["P1-02 receiving occupancy"] = { "receiving_lanes_report_full", "receiving_lane_reopens_after_move" },
    ["P1-03 physical cutter logistics"] = { "cutter_rejects_far_floor_pallet", "cutter_output_is_safe_floor" },
    ["P1-04 lift workload"] = { "six_lift_checkpoint_round_trip", "cutter_repeat_lift_requires_manual_cutting" },
    ["P1-05 crash-safe saves"] = { "save_truncated_primary_recovers_backup", "save_invalid_primary_recovers_valid_temporary" },
    ["P2-01 unfinished press boundary"] = { "picture_press_excluded_from_runtime" },
    ["P2-02 vendor supply consumers"] = { "vendor_wrapper_consumes_delivered_supplies", "sample_cutter_consumes_delivered_paper" },
    ["P2-03 input documentation"] = { "title_keyboard_c_continues", "computer_back_escape_parity" },
    ["P2-04 vendor close parity"] = { "vendor_back_escape_parity" },
    ["P2-05 movement footprints"] = { "wrapper_full_footprint_move_and_operator_walk", "pallet_drop_rejects_blocked_corner" },
    ["P2-06 asset diagnostics"] = { "asset_diagnostic_names_missing_path", "asset_diagnostic_explains_malformed_dimensions" },
    ["P2-07 office status views"] = { "domain_office_purchase_order_projection", "computer_status_vocabulary" },
    ["P2-08 exact atlas grids"] = { "polar_back_button_frame_3", "boxed_paper_pallet_stage_5_direction_4" },
    ["P3-01 retained texture memory"] = { "startup_texture_memory_below_100_mib", "domain_asset_pack_transitions" },
}

local function idFor(finding)
    return finding:match("^(P%d%-%d+)"):lower():gsub("%-", "_")
end

function Coverage.run(passed, check)
    for finding, requiredChecks in pairs(FINDINGS) do
        local missing = {}
        for _, name in ipairs(requiredChecks) do
            if not passed[name] then missing[#missing + 1] = name end
        end
        check("audit_" .. idFor(finding) .. "_covered", #missing == 0,
            finding .. " missing: " .. table.concat(missing, ", "))
    end
end

return Coverage
