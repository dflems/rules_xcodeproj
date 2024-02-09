"""Module for defining custom Xcode schemes (`.xcscheme`s)."""

load(
    "//xcodeproj/internal:memory_efficiency.bzl",
    "EMPTY_STRING",
    "FALSE_ARG",
    "TRUE_ARG",
)
load("//xcodeproj/internal:platforms.bzl", "platforms")

_XCODE_PREVIEW_PRODUCT_TYPES = {
    "A": None,  # com.apple.product-type.application.on-demand-install-capable
    "B": None,  # com.apple.product-type.bundle
    "E": None,  # com.apple.product-type.extensionkit-extension
    "T": None,  # com.apple.product-type.tool
    "a": None,  # com.apple.product-type.application
    "e": None,  # com.apple.product-type.app-extension
    "f": None,  # com.apple.product-type.framework
    "t": None,  # com.apple.product-type.tv-app-extension
    "u": None,  # com.apple.product-type.bundle.unit-test
    "w": None,  # com.apple.product-type.application.watchapp2
}

_EXECUTION_ACTION_NAME = struct(
    build = "build",
    profile = "profile",
    run = "run",
    test = "test",
)

# enum of flags, mainly to ensure the strings are frozen and reused
_FLAGS = struct(
    colorize = "--colorize",
    consolidation_maps = "--consolidation-maps",
    target_and_extension_hosts = "--target-and-extension-hosts",
)

def _hosted_target(hosted_target):
    return [hosted_target.hosted, hosted_target.host]

def _is_same_platform_xcode_preview_target(*, platform, xcode_target):
    if not xcode_target:
        return False
    if not platforms.is_same_type(platform, xcode_target.platform):
        return False
    return xcode_target.product.type in _XCODE_PREVIEW_PRODUCT_TYPES

def _null_newlines(str):
    return str.replace("\n", "\0")

# API

def _write_schemes(
        *,
        actions,
        autogeneration_mode,
        colorize,
        consolidation_maps,
        default_xcode_configuration,
        extension_point_identifiers_file,
        generator_name,
        hosted_targets,
        include_transitive_preview_targets,
        install_path,
        targets_args,
        targets_env,
        tool,
        workspace_directory,
        xcode_targets,
        xcscheme_infos):
    """Creates the `.xcscheme` `File`s for a project.

    Args:
        actions: `ctx.actions`.
        autogeneration_mode: Specifies how Xcode schemes are automatically
            generated.
        colorize: A `bool` indicating whether to colorize the output.
        consolidation_maps: A `list` of `File`s containing target consolidation
            maps.
        default_xcode_configuration: The name of the the Xcode configuration to
            use when building, if not overridden by custom schemes.
        extension_point_identifiers_file: A `File` that contains a JSON
            representation of `[TargetID: ExtensionPointIdentifier]`.
        generator_name: The name of the `xcodeproj` generator target.
        hosted_targets: A `depset` of `struct`s with `host` and `hosted` fields.
            The `host` field is the target ID of the hosting target. The
            `hosted` field is the target ID of the hosted target.
        include_transitive_preview_targets: Whether to adjust schemes to
            explicitly include transitive dependencies that are able to run
            Xcode Previews.
        install_path: The workspace relative path to where the final
            `.xcodeproj` will be written.
        targets_args: A `dict` mapping `xcode_target.id` to `list` of
            command-line arguments.
        targets_env: A `dict` mapping `xcode_target.id` to `list` of environment
            variable `tuple`s.
        tool: The executable that will generate the output files.
        workspace_directory: The absolute path to the Bazel workspace
            directory.
        xcode_targets: A `dict` mapping `xcode_target.id` to `xcode_target`s.
        xcscheme_infos: A `list` of `struct`s as returned` by
            `xcscheme_infos.from_json`.

    Returns:
        A `tuple` with two elements:

        *   A `File` for the directory containing the `.xcscheme`s.
        *   The `xcschememanagement.plist` `File`.
    """

    output = actions.declare_directory(
        "{}_pbxproj_partials/xcschemes".format(generator_name),
    )
    xcschememanagement = actions.declare_file(
        "{}_pbxproj_partials/xcschememanagement.plist".format(generator_name),
    )

    execution_actions_file = actions.declare_file(
        "{}_pbxproj_partials/execution_actions_file".format(generator_name),
    )
    targets_args_env_file = actions.declare_file(
        "{}_pbxproj_partials/targets_args_env_file".format(generator_name),
    )
    custom_schemes_file = actions.declare_file(
        "{}_pbxproj_partials/custom_schemes_file".format(generator_name),
    )

    inputs = consolidation_maps + [
        custom_schemes_file,
        execution_actions_file,
        extension_point_identifiers_file,
        targets_args_env_file,
    ]

    args = actions.args()
    args.use_param_file("@%s")
    args.set_param_file_format("multiline")

    execution_actions_args = actions.args()
    execution_actions_args.set_param_file_format("multiline")

    targets_args_env_args = actions.args()
    targets_args_env_args.set_param_file_format("multiline")

    custom_scheme_args = actions.args()
    custom_scheme_args.set_param_file_format("multiline")

    # outputDirectory
    args.add_all([output], expand_directories = False)

    # schemeManagementOutputPath
    args.add(xcschememanagement)

    # autogenerationMode
    args.add(autogeneration_mode)

    # defaultXcodeConfiguration
    args.add(default_xcode_configuration)

    # workspace
    args.add(workspace_directory)

    # installPath
    args.add(install_path)

    # extensionPointIdentifiersFile
    args.add(extension_point_identifiers_file)

    # executionActionsFile
    args.add(execution_actions_file)

    # targetsArgsEnvFile
    args.add(targets_args_env_file)

    # customSchemesFile
    args.add(custom_schemes_file)

    # transitivePreviewTargetsFile
    if include_transitive_preview_targets:
        transitive_preview_targets_file = actions.declare_file(
            "{}_pbxproj_partials/transitive_preview_targets_file".format(
                generator_name,
            ),
        )
        inputs.append(transitive_preview_targets_file)
        args.add(transitive_preview_targets_file)

        transitive_preview_targets_args = actions.args()
        transitive_preview_targets_args.set_param_file_format("multiline")

        for xcode_target in xcode_targets.values():
            if xcode_target.product.type in _XCODE_PREVIEW_PRODUCT_TYPES:
                ids = [
                    id
                    for id in xcode_target.transitive_dependencies.to_list()
                    if _is_same_platform_xcode_preview_target(
                        platform = xcode_target.platform,
                        xcode_target = xcode_targets.get(id),
                    )
                ]
                if ids:
                    transitive_preview_targets_args.add(xcode_target.id)
                    transitive_preview_targets_args.add_all(
                        ids,
                        omit_if_empty = False,
                        terminate_with = "",
                    )

        actions.write(
            transitive_preview_targets_file,
            transitive_preview_targets_args,
        )
    else:
        args.add(EMPTY_STRING)

    # consolidationMaps
    args.add_all(_FLAGS.consolidation_maps, consolidation_maps)

    # targetAndExtensionHosts
    args.add_all(
        _FLAGS.target_and_extension_hosts,
        hosted_targets,
        map_each = _hosted_target,
    )

    # TargetArgsAndEnv

    targets_args_env_args.add(len(targets_args))
    for id, target_args in targets_args.items():
        targets_args_env_args.add(id)
        targets_args_env_args.add(len(target_args))
        targets_args_env_args.add_all(target_args, map_each = _null_newlines)

    targets_args_env_args.add(len(targets_env))
    for id, target_env in targets_env.items():
        targets_args_env_args.add(id)
        targets_args_env_args.add(len(target_env))
        for key, value in target_env:
            targets_args_env_args.add_all(
                [key, value],
                map_each = _null_newlines,
            )

    # CreateCustomSchemeInfos

    def _add_args(args):
        if args == None:
            custom_scheme_args.add(-1)
            return
        custom_scheme_args.add(len(args))
        for arg in args:
            custom_scheme_args.add_all([arg.value], map_each = _null_newlines)
            custom_scheme_args.add(arg.enabled)

    # buildifier: disable=uninitialized
    def _add_build_targets(build_targets, *, action_name, scheme_name):
        # A build target can be listed multiple times, in the case of target
        # merging, or different pre/post action declarations. Let's unique the
        # ids before sending them over.
        for id in {t.id: None for t in build_targets}:
            custom_scheme_args.add(id)

        for build_target in build_targets:
            _add_execution_actions(
                build_target,
                target_id = build_target.id,
                action_name = action_name,
                scheme_name = scheme_name,
            )
        custom_scheme_args.add("")

    def _add_diagnostics(diagnostics):
        custom_scheme_args.add(diagnostics.address_sanitizer)
        custom_scheme_args.add(diagnostics.thread_sanitizer)
        custom_scheme_args.add(diagnostics.undefined_behavior_sanitizer)

    def _add_env(env):
        if env == None:
            custom_scheme_args.add(-1)
            return

        custom_scheme_args.add(len(env))

        # buildifier: disable=uninitialized
        for key, env in env.items():
            custom_scheme_args.add_all(
                [key, env.value],
                map_each = _null_newlines,
            )
            custom_scheme_args.add(env.enabled)

    # buildifier: disable=uninitialized
    def _add_execution_action(
            action,
            *,
            action_name,
            id,
            is_pre_action,
            scheme_name):
        execution_actions_args.add(scheme_name)
        execution_actions_args.add(
            _EXECUTION_ACTION_NAME.build if action.for_build else action_name,
        )
        execution_actions_args.add(is_pre_action)
        execution_actions_args.add_all(
            [action.title, action.script_text],
            map_each = _null_newlines,
        )
        execution_actions_args.add(id or "")
        execution_actions_args.add(action.order or "")

    # buildifier: disable=uninitialized
    def _add_execution_actions(target, *, target_id, action_name, scheme_name):
        # buildifier: disable=uninitialized
        for action in target.pre_actions:
            _add_execution_action(
                action,
                action_name = action_name,
                id = target_id,
                is_pre_action = TRUE_ARG,
                scheme_name = scheme_name,
            )

        # buildifier: disable=uninitialized
        for action in target.post_actions:
            _add_execution_action(
                action,
                action_name = action_name,
                id = target_id,
                is_pre_action = FALSE_ARG,
                scheme_name = scheme_name,
            )

    # buildifier: disable=uninitialized
    def _add_launch_target(launch_target, *, action_name, scheme_name):
        custom_scheme_args.add(launch_target.is_path)

        if launch_target.is_path == TRUE_ARG:
            target_id = None
            custom_scheme_args.add(launch_target.path)
            custom_scheme_args.add(launch_target.working_directory)
        else:
            target_id = launch_target.id
            custom_scheme_args.add(target_id)
            custom_scheme_args.add(launch_target.extension_host)
            custom_scheme_args.add(launch_target.working_directory)

        _add_execution_actions(
            launch_target,
            target_id = target_id,
            action_name = action_name,
            scheme_name = scheme_name,
        )

    custom_scheme_args.add(len(xcscheme_infos))
    for info in xcscheme_infos:
        scheme_name = info.name
        custom_scheme_args.add(scheme_name)

        # Test

        custom_scheme_args.add(len(info.test.test_targets))
        for test_target in info.test.test_targets:
            custom_scheme_args.add(test_target.id)
            custom_scheme_args.add(test_target.enabled)
            _add_execution_actions(
                test_target,
                target_id = test_target.id,
                action_name = _EXECUTION_ACTION_NAME.test,
                scheme_name = scheme_name,
            )

        _add_build_targets(
            info.test.build_targets,
            action_name = _EXECUTION_ACTION_NAME.test,
            scheme_name = scheme_name,
        )

        _add_args(info.test.args)
        _add_env(info.test.env)
        custom_scheme_args.add(info.test.env_include_defaults)
        custom_scheme_args.add(info.test.use_run_args_and_env)
        _add_diagnostics(info.test.diagnostics)
        custom_scheme_args.add(info.test.xcode_configuration)

        # Run

        _add_build_targets(
            info.run.build_targets,
            action_name = _EXECUTION_ACTION_NAME.run,
            scheme_name = scheme_name,
        )

        _add_args(info.run.args)
        _add_env(info.run.env)
        custom_scheme_args.add(info.run.env_include_defaults)
        _add_diagnostics(info.run.diagnostics)
        custom_scheme_args.add(info.run.xcode_configuration)

        _add_launch_target(
            info.run.launch_target,
            action_name = _EXECUTION_ACTION_NAME.run,
            scheme_name = scheme_name,
        )

        # Profile

        _add_build_targets(
            info.profile.build_targets,
            action_name = _EXECUTION_ACTION_NAME.profile,
            scheme_name = scheme_name,
        )

        _add_args(info.profile.args)
        _add_env(info.profile.env)
        custom_scheme_args.add(info.profile.env_include_defaults)
        custom_scheme_args.add(info.profile.use_run_args_and_env)
        custom_scheme_args.add(info.profile.xcode_configuration)

        _add_launch_target(
            info.profile.launch_target,
            action_name = _EXECUTION_ACTION_NAME.profile,
            scheme_name = scheme_name,
        )

    # colorize
    if colorize:
        args.add(_FLAGS.colorize)

    actions.write(execution_actions_file, execution_actions_args)
    actions.write(targets_args_env_file, targets_args_env_args)
    actions.write(custom_schemes_file, custom_scheme_args)

    actions.run(
        arguments = [args],
        executable = tool,
        inputs = inputs,
        outputs = [output, xcschememanagement],
        progress_message = "Creating '.xcschemes' for {}".format(install_path),
        mnemonic = "WriteXCSchemes",
        execution_requirements = {
            # Lots of files to read and write, so lets have some speed
            "no-sandbox": "1",
        },
    )

    return (output, xcschememanagement)

# API

xcschemes_execution = struct(
    write_schemes = _write_schemes,
)
