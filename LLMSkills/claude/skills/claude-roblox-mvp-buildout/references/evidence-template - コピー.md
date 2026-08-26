# MVP検証証跡テンプレート

このファイルを実行ごとに複製する。空欄を合格扱いしない。値を取得できない項目は `UNVERIFIED` と理由を書く。

## 1. 実行識別

- run_id:
- started_at_utc:
- operator:
- objective:
- repository_root:
- repository_physical_root / git_dir / git_common_dir:
- trusted_evidence_root / physical_root:
- evidence_root_local_fixed / repo_temp_git_admin_disjoint:
- evidence_root_owner_provisioned / access_boundary / no_active_workspace_writer:
- unique_run_directory / creation_result:
- branch:
- head_sha:
- initial_status_porcelain_z_artifact:
- pre_existing_change_ledger:
- owned_paths:
- frozen_paths:

## 2. 承認

- specification_version / approver:
- OS_input_consent / approval_id / exact_action / target_run_pid_role / scope / approver / time:
- fullscreen_capture_consent / approver / time:
- existing_evidence_overwrite_consent / approver / time:
- process_close_consent / approval_id / exact_cleanup_action / target_pid_list / scope / approver / time:
- force_close_consent / approver / time:
- desktop_session_change_consent / approver / time:
- commit_consent / approver / time:
- push_consent / approver / time:
- publish_consent / approver / time:
- autonomous_execution_surfaces_available (studio_mcp / computer_use / browser / local。各 available|unavailable と実出力):
- autonomous_actions_self_executed (自分で実行し自分で判定した操作の一覧。各に生出力のpath):
- blocked_safety_items (§1.1の線に触れて実行しなかった操作 / 理由 / 再開条件):
- delegation_worker / tier (T1|T2|T3) / model_id / version / auth_channel / designated_by (owner|asked) / time:
- delegation_destination_orgs (送信先事業者。T3は背後のmodel提供者も列挙):
- delegation_data_submission_consent / approved_prompt_repo_read_scope / excluded_secrets / approver / time:
- delegation_enforcement_gap (T2/T3のとき、失われる強制機構と人手での代替):
- delegation_worker_changed_midrun / reason / completed_WPs_at_change:
- codex_API_key_environment_consent / approver / time / auth_channel:   # T1
- codex_Windows_read_exposure / dedicated_OS_account_or_VM / all_readable_local_data_consent / AllowWindowsAccountReadExposure / approver / time:   # T1
- gameplay_rule_or_Tier0_change_approvals:
- known_defect_waivers:

## 3. 環境

- OS / interactive_desktop / session_id:
- PowerShell_version:
- PowerShell_host_exact_path / Authenticode / sha256 / NoProfile_NonInteractive / per_process_ExecutionPolicy_Bypass / command_provenance_gate:
- bundled_helper_fresh_process_contract / one_invocation_per_OS_process / trusted_PSModulePath:
- Studio_path / product_version / sha256:
- Studio_Authenticode_status / signer_subject / signer_thumbprint:
- Studio_owner_approved_inventory_path / executable_directory_working_directory:
- Studio_install_and_evidence_same_user_writer_absent / residual_trust_assumption:
- Studio_MCP_capabilities:
- StudioTestService_available:
- VirtualInput_available:
- git_version:
- builder / version / lockfile:
- Luau_parser_linter / version:
- codex_cli_version / auth_preflight / bounded_preflight_result:
- codex_exact_supported_version: codex-cli 0.147.0 / upgrade_reaudit:
- codex_DryRun_config_loader_invoked: no / pending_actual_preflight:
- codex_external_account_billing_identity_check / source / approver / time:
- git_launcher_path / physical_path / sha256 / signer / product_version:
- git_direct_common_dir / system_global_config_disabled:
- git_local_config_path / length / strict_UTF8 / sha256 / file_identity / single_hardlink:
- git_local_config_safe_key_allowlist / include_command_surface_absent / lifetime_read_lock:
- codex_launcher_path / physical_path / sha256 / signer / trusted_working_directory:
- codex_skill_script_directory_physical_disjoint:
- codex_worker_path / canonical_path / sha256 / single_hardlink / file_identity / self_verification:
- codex_direct_worktree / project_config_and_hooks_absent / ignored_user_config_and_rules:
- codex_home_path / physical_path / local_fixed_nonreparse_disjoint:
- codex_home_user_config_and_instruction_layers_absent:
- codex_auth_channel / API_key_explicitly_approved / API_key_value_logged: no
- codex_network_environment_contract / shell_environment_contract / ambient_secret_scan:
- codex_strict_config / openai_provider / network_and_temp_disabled:
- codex_optional_features_disabled / feature_preflight / unknown_config_warnings:
- codex_PATH_PATHEXT_current_directory_contract / login_shell_profile_disabled / child_and_tool_PSModulePath:
- codex_repo_gitdir_commondir_temp_output_disjoint:
- codex_output_ACL_owner_provisioned / same_user_writer_absent / residual_trust_assumption:
- prompt_path / length_bytes / max_bytes: 8388608
- prompt_single_hardlink / handle_identity / bytes_sha256:
- preflight_stdout_stderr_max_bytes: 1048576 each
- job_stdout_stderr_max_bytes: 67108864 each
- stdout_bytes / stderr_bytes / output_limit_exceeded:
- metadata_schema_version / worker_pid / launcher_pid / terminal_state / exit_code:

## 4. ビルド同一性

- input_head_sha:
- build_command:
- build_1_path / size / sha256:
- build_2_path / size / sha256:
- deterministic_match:
- retained_test_artifact_path:
- retained_artifact_inside_trusted_evidence_root:
- test_artifact_read_only:
- pre_launch_sha256:
- post_close_sha256:
- tested_artifact_unchanged:

## 5. Studioセッション

- session_manifest_path:
- session_manifest_schema_version: 7
- caller_repository_root / caller_trusted_evidence_root:
- scripts_root / physical_root / repo_git_temp_evidence_disjoint:
- session_script_path / sha256 / file_identity:
- input_script_path / sha256 / file_identity / memory_snapshot_verified:
- capture_script_path / sha256 / file_identity / memory_snapshot_verified:
- Studio_version_directory / repo_git_temp_evidence_disjoint:
- ownership_id:
- session_id:
- session_manifest_operator / creation_command:
- session_file_mutex / bounded_acquire_result / abandoned_or_timeout: no
- pending_action_journal_schema_version: 1
- pending_action_journal_path / action_id / action / created_before_effect / cleared_after_commit:
- pending_action_session_file / ownership_id / manifest_sha_before / target_intent / caller_pid_session_sid_host / file_identity:
- last_completed_external_action / result_binding_sha256 / completion_manifest_sha256:
- prior_pending_journal_detected / manual_PID_manifest_output_reconciliation / owner_resolution:
- missing_structured_response / last_completed_action_checked_before_retry / duplicate_effect_avoided:
- pid / start_time_utc / session_id / executable_path / player mapping:
- candidate_launch_intent / observed_role / role_verified:
- role_handshake_source / probe_id / event_id / observed_at_utc / expires_at_utc:
- role_refresh_event_id / probe_id / observed_at_utc / previous_event_id:
- role_evidence_path / sha256 / original_log_or_MCP_query:
- evidence_source_authenticated: no | external mechanism and limitation
- role_evidence_valid_at_input_or_cleanup:
- place_handshake_verified:
- observed_place_or_build_sha256:
- place_evidence_path / sha256 / original_log_or_MCP_query / expires_at_utc:
- place_refresh_event_id / probe_id / observed_at_utc / previous_event_id:
- place_evidence_valid_at_input_or_cleanup:
- authoritative_server_pid / roster_query:
- target_client_pid / launch_intent / player_id / player_name:
- join_event_id / observed_at_utc / participation_evidence_path / sha256:
- input_method: StudioTestService | VirtualInput | OS SendInput | none
- OS_input_plan_dry_run_result:
- OS_input_deadline_utc / conservative_plan_deadline_check / per_action_deadline_check:
- OS_input_owner_approval_id / exact_action_scope / valid_at_dispatch:
- OS_input_identity_revalidated_after_approval / pid_start_executable_signer_session_role_place_hwnd_foreground:
- OS_input_authorization_asserted:  # helper switch。owner approvalやidentity再検証の代替ではない
- coordinate_evidence_run_id / target_pid / start_time / session / executable_path / window_handle:
- coordinate_capture_path / capture_sha256 / captured_at_utc / measured_points:
- coordinate_capture_width / height / current_window_width / height / freshness_expires_at:
- coordinate_binding_revalidated_before_dispatch:
- exact_main_hwnd / foreground_hwnd / owner_pid_at_dispatch:
- virtual_screen_origin_x / origin_y / width / height:
- privacy_preflight:
- capture_mode / output_path / output_sha256 / existing_file_replaced:
- session_Action_Capture / target_owned_role_place_revalidated / direct_helper_rejected:
- capture_result_json_path / sha256 / parser_engine_version:
- capture_used_same_preflight_trusted_root / output_bytes / captured_at_utc:
- capture_timeout_seconds / worker_pid / timeout_result:
- capture_width / height / pixel_count / raw_bytes / png_bytes / configured_limits:
- cleanup_owner_approval_id / exact_target_pid_list / valid_at_dispatch:
- cleanup_identity_revalidated_after_approval / pid_start_executable_signer_session_role_place_hwnd_owner:
- cleanup_dispose_restore_remove_results / final_owned_pid_state:

## 6. テスト結果

各テストIDについて次を繰り返す。

- test_id:
- requirement_id:
- build_sha256:
- expected:
- action_or_probe:
- structured_event_id / timestamp / log_artifact:
- authoritative_state_query / actual:
- client_UI_or_player_query / actual:
- image_or_video_artifact:
- error_count / rejection_count / retry_count / counted_range:
- result: PASS | FAIL | BLOCKED | UNVERIFIED
- limitation:

## 7. WPと差分

- wp_id:
- allowed_paths:
- actual_changed_paths:
- static_checks / result:
- smoke_manifest / server-client-shared result:
- deterministic_build_result:
- milestone_live_test_ids:
- commit_approval:
- commit_sha:
- D6_code_tests_progress_changelog_traceability_affected_specs_synced_revision:
- lkg_kind: owner-approved-commit | immutable-snapshot
- lkg_snapshot_id / head / initial_status_artifact / owned_diff_sha256 / untracked_manifest_sha256:
- contract_conflict_detected / WP_stopped:
- change_request_id / affected_specs_tests_WPs_traceability:
- D4_reaudit / P0_reapproval / D5_reapproval:

## 8. 引き渡し

- completed_claims:
- provisional_values:
- operator_decisions:
- observations_requiring_owner_decision:
- accepted_defects_and_approval:
- unverified_claims:
- remaining_pre_existing_changes:
- push_or_publish_status:
