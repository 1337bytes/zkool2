"""Exercise workspace discovery against real, dependency-free Cargo workspaces."""
import importlib.util
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / "build-apple.py"
SPEC = importlib.util.spec_from_file_location("build_apple", SCRIPT)
BUILD = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BUILD)


class WorkspaceIntegrationTests(unittest.TestCase):
    def check_workspace(self, include_native, include_graphql, include_payments=True):
        with tempfile.TemporaryDirectory() as directory:
            workspace = Path(directory)
            members = '["rust", "native/rust"]' if include_native else '["rust"]'
            (workspace / "Cargo.toml").write_text(
                f'[workspace]\nmembers = {members}\nresolver = "2"\n'
            )
            for path, name in [("rust", "rlz"), ("native/rust", "zkool-native")]:
                crate = workspace / path
                (crate / "src").mkdir(parents=True)
                features = '\n[features]\ngraphql-core = []\n' if include_graphql and name == "rlz" else ""
                (crate / "Cargo.toml").write_text(
                    f'[package]\nname = "{name}"\nversion = "0.1.0"\nedition = "2021"\n{features}'
                )
                (crate / "src" / "lib.rs").write_text("")
            if include_payments:
                payment_api = workspace / "rust" / "src" / "api" / "pay.rs"
                payment_api.parent.mkdir()
                payment_api.write_text("\n".join(
                    f"pub async fn {name}() {{}}" for name in
                    ("prepare_software_payment", "submit_software_payment", "spendable_pools")
                ))
            with patch.multiple(BUILD, ROOT=workspace / "native", WORKSPACE=workspace,
                                MANIFEST=workspace / "native" / "rust" / "Cargo.toml"):
                return BUILD.workspace_metadata()

    def test_native_directory_without_workspace_change(self):
        with self.assertRaisesRegex(SystemExit, 'Add "native/rust"'):
            self.check_workspace(include_native=False, include_graphql=True)

    def test_missing_core_integration(self):
        with self.assertRaisesRegex(SystemExit, "Missing graphql-core"):
            self.check_workspace(include_native=True, include_graphql=False)

    def test_registered_native_package_is_discovered(self):
        metadata = self.check_workspace(include_native=True, include_graphql=True)
        self.assertEqual({p["name"] for p in metadata["packages"]}, {"rlz", "zkool-native"})

    def test_missing_payment_core_update_has_actionable_error(self):
        with self.assertRaisesRegex(SystemExit, "Copy the updated zkool2/rust/src/api/pay.rs"):
            self.check_workspace(include_native=True, include_graphql=True, include_payments=False)


class AppleEnvironmentTests(unittest.TestCase):
    def test_device_and_simulator_override_stale_sdk_and_minimum_version(self):
        for triple, sdk in [("aarch64-apple-ios", "iphoneos"),
                            ("aarch64-apple-ios-sim", "iphonesimulator")]:
            with self.subTest(target=triple), patch.dict(os.environ, {
                "SDKROOT": "/wrong/sdk", "IPHONEOS_DEPLOYMENT_TARGET": "10.0"
            }), patch.object(BUILD.subprocess, "check_output", return_value=f"/Xcode/{sdk}.sdk\n") as lookup:
                environment = BUILD.ios_build_environment(triple)
                self.assertEqual(environment["IPHONEOS_DEPLOYMENT_TARGET"], "16.0")
                self.assertEqual(environment["SDKROOT"], f"/Xcode/{sdk}.sdk")
                self.assertEqual(lookup.call_args.args[0], ["xcrun", "--sdk", sdk, "--show-sdk-path"])
                # Cross-build settings must not leak into the host bindgen build.
                self.assertEqual(os.environ["IPHONEOS_DEPLOYMENT_TARGET"], "10.0")
                self.assertEqual(os.environ["SDKROOT"], "/wrong/sdk")

    def test_environment_reaches_cargo_subprocess(self):
        environment = {"IPHONEOS_DEPLOYMENT_TARGET": "16.0"}
        with patch.object(BUILD.subprocess, "run") as execute:
            BUILD.cargo("build", "--target", "aarch64-apple-ios", env=environment)
            self.assertIs(execute.call_args.kwargs["env"], environment)

    def test_app_and_rust_minimum_versions_match(self):
        project = (SCRIPT.parent / "ios" / "project.yml").read_text()
        self.assertIn(f'iOS: "{BUILD.IOS_DEPLOYMENT_TARGET}"', project)


if __name__ == "__main__":
    unittest.main()
