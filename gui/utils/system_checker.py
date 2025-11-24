"""
System Checker - システム要件と環境状態の確認

Julia、データディレクトリ、スクリプトの存在を確認し、
GUI上でシステム状態を表示するための情報を提供します。
"""

import os
import subprocess
from pathlib import Path
from typing import Dict, Tuple


class SystemChecker:
    """システム要件チェッカー"""

    def __init__(self, project_root: Path):
        """
        Args:
            project_root: プロジェクトルートディレクトリ
        """
        self.project_root = project_root
        self.julia_path = Path.home() / ".juliaup" / "bin" / "julia"

    def check_all(self) -> Dict[str, Tuple[bool, str]]:
        """
        全システム要件をチェック

        Returns:
            Dict[項目名, (成功/失敗, メッセージ)]
        """
        results = {}

        # Julia チェック
        results["Julia"] = self._check_julia()

        # データディレクトリ チェック
        results["Data Dirs"] = self._check_data_dirs()

        # スクリプト チェック
        results["Scripts"] = self._check_scripts()

        # Julia Project チェック
        results["Julia Project"] = self._check_julia_project()

        return results

    def _check_julia(self) -> Tuple[bool, str]:
        """Julia インストール確認"""
        if not self.julia_path.exists():
            return False, f"Julia not found at {self.julia_path}"

        try:
            result = subprocess.run(
                [str(self.julia_path), "--version"],
                capture_output=True,
                text=True,
                timeout=5
            )
            version = result.stdout.strip()
            return True, version
        except Exception as e:
            return False, f"Error checking Julia: {e}"

    def _check_data_dirs(self) -> Tuple[bool, str]:
        """データディレクトリ存在確認"""
        data_root = self.project_root / "data"
        logs_dir = data_root / "logs"
        training_dir = data_root / "training"
        models_dir = data_root / "models"

        missing = []
        if not data_root.exists():
            missing.append("data/")
        if not logs_dir.exists():
            missing.append("data/logs/")
        if not training_dir.exists():
            missing.append("data/training/")
        if not models_dir.exists():
            missing.append("data/models/")

        if missing:
            return False, f"Missing: {', '.join(missing)}"

        # ファイル数をカウント
        log_count = len(list(logs_dir.glob("*.jld2")))
        training_count = len(list(training_dir.glob("*.jld2")))
        model_count = len(list(models_dir.glob("*.jld2")))

        return True, f"Logs: {log_count}, Training: {training_count}, Models: {model_count}"

    def _check_scripts(self) -> Tuple[bool, str]:
        """重要なスクリプト存在確認"""
        scripts_dir = self.project_root / "scripts"
        required_scripts = [
            "run_basic_validation.sh",
            "test_phase2_haze.jl",
            "baseline_comparison.jl",
            "shepherding_experiment.jl"
        ]

        missing = []
        for script in required_scripts:
            if not (scripts_dir / script).exists():
                missing.append(script)

        if missing:
            return False, f"Missing: {', '.join(missing)}"

        return True, f"{len(required_scripts)} scripts found"

    def _check_julia_project(self) -> Tuple[bool, str]:
        """Julia プロジェクト設定確認"""
        project_toml = self.project_root / "src_julia" / "Project.toml"
        manifest_toml = self.project_root / "src_julia" / "Manifest.toml"

        if not project_toml.exists():
            return False, "Project.toml not found"

        if not manifest_toml.exists():
            return False, "Manifest.toml not found (run: julia --project=src_julia -e 'using Pkg; Pkg.instantiate()')"

        return True, "Project configured"

    def get_julia_command(self, script_path: str) -> list:
        """
        Juliaスクリプト実行用のコマンドラインを生成

        Args:
            script_path: 実行するJuliaスクリプト（プロジェクトルートからの相対パス）

        Returns:
            コマンドライン配列
        """
        return [
            str(self.julia_path),
            f"--project={self.project_root / 'src_julia'}",
            str(self.project_root / script_path)
        ]

    def get_bash_command(self, script_path: str) -> list:
        """
        bashスクリプト実行用のコマンドラインを生成

        Args:
            script_path: 実行するbashスクリプト（プロジェクトルートからの相対パス）

        Returns:
            コマンドライン配列
        """
        return ["bash", str(self.project_root / script_path)]
