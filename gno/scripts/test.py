"""Runs the tests of gno's Wormhole realms.

From gno/, with GNOROOT naming a checkout of gno at the commit the Dockerfile
pins, and the gno binary built from it on PATH or named by GNO:

    python3 scripts/test.py [--keep]

Each realm's committed config.gno fails closed, so the realms can't be tested
in place. The runner builds a temporary gno workspace laid out by module path:
the five modules, the gno example packages they import, copied from
GNOROOT/examples, and the test-only realms of testdata/realms. It swaps a test
configuration, on gno's test chain ID dev, in for each realm's config.gno, and
writes one filetest per corpus scenario (corpus.py). Then:

- each module's tests and filetests must all pass;
- Core, the vault and the logic run under the configurations their main runs
  can't use: each refusal must fail with its named reason, and each variant
  must pass its filetests from testdata/core-variant or testdata/logic-variant;
- no deployable file may import a test-only realm;
- gno must have fetched nothing: GNOHOME starts empty and its package cache
  must stay so.
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

# corpus.py sits beside this script. Importing it writes no __pycache__ into
# the checkout.
sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
import corpus  # noqa: E402

GNO_DIR = Path(__file__).resolve().parents[1]
TESTDATA = GNO_DIR / "testdata"
CORE = "gno.land/r/wormhole/core"
VAA = "gno.land/p/wormhole/vaa/v0"
VAULT = "gno.land/r/wormhole/tokenbridge"
LOGIC = corpus.LOGIC
LIB = "gno.land/p/wormhole/tokenbridge/v0"
LOGIC_V2 = "gno.land/r/wormhole/tokenbridge/logic/v2"
LOGIC_V3 = "gno.land/r/wormhole/tokenbridge/logic/v3"
MODULES = (CORE, VAA, VAULT, LOGIC, LIB)
# The gno example packages Core and the vault import, and those they import.
DEPENDENCIES = ("gno.land/p/nt/avl/v0", "gno.land/p/nt/avl/rotree/v0", "gno.land/p/nt/cford32/v0",
                "gno.land/p/nt/fqname/v0", "gno.land/p/nt/grc20/v0", "gno.land/p/nt/markdown/sanitize/v0",
                "gno.land/p/moul/md/v0", "gno.land/p/nt/seqid/v0", "gno.land/p/nt/ufmt/v0", "gno.land/r/nt/grc20reg/v0")
# Limits that bind nothing, and the small ones of the limits variant: per
# transfer, outbound in 24 hours, inbound in 24 hours.
NO_LIMITS = (2**63 - 1,) * 3
SMALL_LIMITS = (100, 150, 1000)
# The wrapped assets the logic's named filetests allowlist beside the corpus's:
# two tokens of chain 2 whose AssetMeta both say WETH.
NAMED_ASSETS = ("2:000000000000000000000000c000000000000000000000000000000000000002",
                "2:000000000000000000000000c000000000000000000000000000000000000003")
# Filetests that import a realm, so that its init runs, for the refusal runs.
CORE_INIT_PROBE = """// PKGPATH: gno.land/r/wormhole_test/probe
package probe

import "gno.land/r/wormhole/core"

func main() {
	println(core.ChainID())
}

// Output:
// 65535
"""
VAULT_INIT_PROBE = """// PKGPATH: gno.land/r/wormhole_test/probe
package probe

import "gno.land/r/wormhole/tokenbridge"

func main() {
	println(tokenbridge.Logic())
}

// Output:
// gno.land/r/wormhole/tokenbridge/logic/v1
"""
LOGIC_INIT_PROBE = """// PKGPATH: gno.land/r/wormhole_test/probe
package probe

import "gno.land/r/wormhole/tokenbridge/logic/v1"

func main() {
	println(logic.Allowlisted(0, ""))
}

// Output:
// false
"""


class Failure(Exception):
    pass


def fail(message):
    raise Failure(message)


class Run:
    """What every gno run shares: the binary, GNOROOT, the environment with its
    own GNOHOME, the scratch directory and the corpora."""

    def __init__(self, gno, gnoroot, scratch):
        self.gno, self.gnoroot, self.scratch = gno, gnoroot, scratch
        self.home = scratch / "gnohome"
        self.home.mkdir()
        self.env = dict(os.environ, GNOROOT=str(gnoroot), GNOHOME=str(self.home))
        self.core_corpus = json.loads((TESTDATA / "core-vectors.json").read_text())
        self.tb_corpus = json.loads((TESTDATA / "tokenbridge-vectors.json").read_text())
        self.bridge_codes = json.loads((TESTDATA / "tokenbridge-reason-codes.json").read_text())
        self.modules = module_dirs()

    def gno_run(self, args, cwd):
        return subprocess.run([str(self.gno), *args], cwd=cwd, env=self.env, text=True, errors="replace",
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT)

    def test(self, cwd):
        return self.gno_run(["test", "-root-dir", str(self.gnoroot), "-v", "-timeout", "10m", "."], cwd)


def declared_module(folder):
    """The module path a folder's gnomod.toml declares."""
    modules = re.findall(r'^module\s*=\s*"([^"\\]+)"\s*$', (folder / "gnomod.toml").read_text(), re.M)
    if len(modules) != 1:
        fail(f"{folder}/gnomod.toml declares {len(modules)} modules, not one")
    return modules[0]


def module_dirs():
    """The realms' modules, by module path: each folder of gno/ outside
    testdata/ holding a gnomod.toml. They must be exactly MODULES."""
    found = {}
    for gnomod in sorted(GNO_DIR.rglob("gnomod.toml")):
        if TESTDATA in gnomod.parents:
            continue
        found[declared_module(gnomod.parent)] = gnomod.parent
    if sorted(found) != sorted(MODULES):
        fail(f"gno/ holds the modules {sorted(found)}, not {sorted(MODULES)}")
    return found


def copy_module(source, dest):
    """A module's own files, as gno reads them: those of its folder, and of its
    subfolders such as filetests/, but not a module nested in it."""
    def ignore(directory, names):
        return [name for name in names if (Path(directory) / name).is_dir()
                and any((Path(directory) / name).rglob("gnomod.toml"))]
    for path in source.rglob("*"):
        if path.is_symlink():
            fail(f"Refusing a symlink: {path}")
    shutil.copytree(source, dest, ignore=ignore, dirs_exist_ok=True)


def fill_workspace(run, workspace):
    """A new gno workspace laid out by module path: the modules, the example
    packages they import and the test-only realms. Returns the test realms'
    paths. Only the realms' own modules may nest, as the logic does in the
    vault's path."""
    realms = {declared_module(folder): folder for folder in sorted((TESTDATA / "realms").iterdir())}
    for path in realms:
        if not path.startswith("gno.land/r/wormhole_test/"):
            fail(f"The test realm {path} is outside gno.land/r/wormhole_test/")
    for path in (*DEPENDENCIES, *realms):
        for other in (*MODULES, *DEPENDENCIES, *realms):
            if other != path and (other.startswith(path + "/") or path.startswith(other + "/")):
                fail(f"{path} and {other} overlap")
    workspace.mkdir()
    (workspace / "gnowork.toml").write_text("")
    for path, folder in run.modules.items():
        copy_module(folder, workspace / path)
    for path in DEPENDENCIES:
        copy_module(run.gnoroot / "examples" / path, workspace / path)
    for path, folder in realms.items():
        copy_module(folder, workspace / path)
    return sorted(realms)


def gno_bytes(data):
    """A Gno string literal holding data."""
    return '"' + "".join(f"\\x{b:02x}" for b in data) + '"'


def core_config(run, gno_chain="dev", replay_above_initial=0, chain_id=None):
    """Core's test configuration: the corpus's chain ID, or chain_id, and its
    initial guardian set, replaying replay_above_initial upgrades."""
    initial = run.core_corpus["initial_guardian_set"]
    keys = b"".join(bytes.fromhex(key.removeprefix("0x")) for key in initial["keys"])
    return f"""package core

// TEST CONFIGURATION written by the test runner from the Core test corpus.
// Public test keys, unsafe for funds.
const (
	wormholeChainID  uint16 = {run.core_corpus["chain_id"] if chain_id is None else chain_id}
	gnoChainID              = "{gno_chain}"
	initialSetIndex  uint32 = {initial["index"]}
	initialKeys             = {gno_bytes(keys)}
	replayUntilIndex uint32 = {initial["index"] + replay_above_initial}
)
"""


def substitute(text, pattern, value, name):
    text, count = re.subn(pattern, value, text, flags=re.M)
    if count != 1:
        fail(f"{name}: {pattern} matches {count} times, not once")
    return text


def vault_config(run, gno_chain="dev", chain_id=None):
    """The vault's test configuration: the committed config.gno with Core's test
    chain ID, or chain_id, and gno_chain."""
    text = (run.modules[VAULT] / "config.gno").read_text()
    wormhole = run.core_corpus["chain_id"] if chain_id is None else chain_id
    text = substitute(text, r"^(\twormholeChainID uint16 = )0$", lambda m: m.group(1) + str(wormhole), VAULT)
    text = substitute(text, r'^(\tgnoChainID +)= ""$', lambda m: m.group(1) + f'= "{gno_chain}"', VAULT)
    return text.replace("package tokenbridge\n", "package tokenbridge\n\n// TEST CONFIGURATION written by "
                        "the test runner.\n", 1)


def logic_config(run, assets, gnot=NO_LIMITS):
    """The logic's test configuration: the committed config.gno with GNOT's limits
    and the allowlist's entries, each an origin ("chain:address" in hex), its
    limits and, optionally, True for exit-only."""
    text = (run.modules[LOGIC] / "config.gno").read_text()
    for name, value in zip(("gnotPerTransfer", "gnotOutboundCap", "gnotInboundBudget"), gnot):
        text = substitute(text, rf"^(\t{name} +int64 = )-1$", lambda m: m.group(1) + str(value), LOGIC)
    rows = ""
    for origin, limits, *exit_only in assets:
        flag = "true" if exit_only and exit_only[0] else "false"
        rows += '\t\t{{{}, "{}", {}, {}, {}, {}}},\n'.format(*origin.split(":"), *limits, flag)
    text = substitute(text, r"^\treturn nil\n", lambda _: "\treturn []assetConfig{\n" + rows + "\t}\n", LOGIC)
    return text.replace("package logic\n", "package logic\n\n// TEST CONFIGURATION written by the test runner.\n", 1)


def no_limit_assets(origins, exit_only=False):
    return [(origin, NO_LIMITS, exit_only) for origin in origins]


def logic_copy(run, workspace, path, config):
    """A logic realm at path: the logic's production files, as a deployment sends
    them, under its own module and configuration. Its path ends in a version,
    so its package name holds."""
    dest = workspace / path
    dest.mkdir(parents=True)
    for source in sorted(run.modules[LOGIC].iterdir()):
        if source.is_file() and source.suffix == ".gno" and not source.name.endswith(("_test.gno", "_filetest.gno")):
            shutil.copyfile(source, dest / source.name)
    (dest / "gnomod.toml").write_text(f'module = "{path}"\ngno = "0.9"\n')
    (dest / "config.gno").write_text(config)


def prepare_core(run, workspace):
    """Core's test configuration and its corpus filetests."""
    core = workspace / CORE
    (core / "config.gno").write_text(core_config(run))
    for scenario in run.core_corpus["scenarios"]:
        (core / "filetests" / corpus.filetest_name(scenario["name"])).write_text(corpus.core_filetest(scenario))


def prepare_logic(run, workspace):
    """The logic's test configuration, on the corpus's allowlist with limits that
    don't bind, logic v2 and v3 for its named filetests, and its corpus
    filetests, with the logic copy each of their allowlist steps switches to."""
    logic = workspace / LOGIC
    allowlisted = no_limit_assets(run.tb_corpus["allowlist"])
    (logic / "config.gno").write_text(logic_config(run, allowlisted))
    for path in (LOGIC_V2, LOGIC_V3):
        logic_copy(run, workspace, path, logic_config(run, allowlisted + no_limit_assets(NAMED_ASSETS)))
    written = set()
    for scenario in run.tb_corpus["scenarios"]:
        text, copies = corpus.tokenbridge_filetest(scenario, run.tb_corpus, run.bridge_codes)
        (logic / "filetests" / corpus.filetest_name(scenario["name"])).write_text(text)
        for path, (allowlist, exit_only) in copies.items():
            if path in written:
                fail(f"Corpus scenario {scenario['name']} switches to {path}, which another step names")
            written.add(path)
            logic_copy(run, workspace, path, logic_config(run, no_limit_assets(allowlist) +
                                                          no_limit_assets(exit_only, exit_only=True)))


def named_tests(package):
    """Every test function and filetest a package declares. gno runs every
    top-level Test function and the filetests of both the package's folder and
    its filetests/ folder."""
    names = []
    for path in sorted(package.glob("*_test.gno")):
        names += re.findall(r"^func (Test\w*)\(", path.read_text(), re.M)
    for folder in (package, package / "filetests"):
        names += [path.name for path in sorted(folder.glob("*_filetest.gno"))]
    if not names:
        fail(f"{package}: no tests")
    return names


def require_passes(output, names):
    """Every named test must have passed: a zero exit alone would also accept a
    run with tests missing or skipped."""
    passed = set()
    for line in output.splitlines():
        line = line.strip()
        # A test's own output may run into the marker, so it is searched for.
        if re.search(r"--- (FAIL|SKIP): ", line):
            fail(f"A gno test did not pass: {line}")
        match = re.match(r"--- PASS: (\S+) \(", line)
        if match:
            name = match.group(1)
            # A filetest reports as <folder>/<file name>.
            passed.add(name.rsplit("/", 1)[-1] if name.endswith("_filetest.gno") else name)
    missing = [name for name in names if name not in passed]
    if missing:
        fail("These gno tests did not pass: " + ", ".join(missing))
    return len(names)


def test_package(run, package, name):
    """Run a package's tests; all of them must pass."""
    result = run.test(package)
    print(result.stdout, end="", flush=True)
    if result.returncode != 0:
        fail(f"{name}: gno test failed")
    count = require_passes(result.stdout, named_tests(package))
    print(f"OK {name}: {count} tests and filetests passed", flush=True)


def require_refusal(name, result, reason, prefix):
    """The run must fail, with the realm's reason, not any other error."""
    if result.returncode == 0 or f"{prefix}: {reason}" not in result.stdout:
        fail(f"{name}: init did not refuse with {prefix}: {reason}:\n{result.stdout}")


def require_test_only_imports(run, workspace, realms):
    """No module imports a test-only realm from its deployable files, as
    committed: this runs before the test configurations replace the realms'
    config.gno. The workspace holds the test realms, so such an import would
    pass here and fail at deployment. Tests and filetests may import them."""
    result = run.gno_run(["list", "-json", *("./" + path for path in MODULES)], workspace)
    if result.returncode != 0:
        fail(f"gno list failed:\n{result.stdout}")
    listed, decoder, rest = {}, json.JSONDecoder(), result.stdout.strip()
    while rest:
        try:
            package, end = decoder.raw_decode(rest)
        except json.JSONDecodeError:
            fail(f"gno list printed something other than JSON: {rest[:200]!r}")
        name = package.get("ImportPath") or package.get("Dir", "?")
        if package.get("Errors"):
            fail(f"gno list: {name}: {package['Errors']}")
        listed[name] = package
        rest = rest[end:].lstrip()
    if sorted(listed) != sorted(MODULES):
        fail(f"gno list reported {sorted(listed)}, not the modules {sorted(MODULES)}")
    if not listed[CORE].get("Imports", {}).get("PackageSource"):
        fail(f"gno list reported no imports for {CORE}; its output has changed shape")
    for path, package in listed.items():
        for imported in package.get("Imports", {}).get("PackageSource", []):
            if imported in realms or imported.startswith("gno.land/r/wormhole_test/"):
                fail(f"{path} imports the test-only realm {imported} outside its tests")
    print("OK no deployable file imports a test-only realm", flush=True)


def clear_tests(package):
    """Remove a package's own tests and filetests from a workspace copy."""
    for test in package.glob("*_test.gno"):
        test.unlink()
    for test in package.glob("*_filetest.gno"):
        test.unlink()
    shutil.rmtree(package / "filetests", ignore_errors=True)
    (package / "filetests").mkdir()


def variant_filetests(folder, package):
    """Copy a variant run's filetests into a package's filetests folder."""
    filetests = sorted(folder.glob("*_filetest.gno"))
    if not filetests:
        fail(f"No filetests in {folder}")
    for filetest in filetests:
        shutil.copyfile(filetest, package / "filetests" / filetest.name)


def core_runs(run):
    """Core under the configurations its main run can't use. init must refuse
    the committed fail-closed configuration and one for another network. With
    one and with two replayed upgrades, and under Wormhole chain ID 258, whose
    two bytes differ unlike 65535's, Core must pass that variant's filetests."""
    cases = (("committed-config-refused", None, "invalid-configuration"),
             ("other-network-refused", core_config(run, gno_chain="gnoland-1"), "wrong-network"),
             ("replay-until-4", core_config(run, replay_above_initial=1), None),
             ("replay-until-5", core_config(run, replay_above_initial=2), None),
             ("chain-id-258", core_config(run, chain_id=258), None))
    variants = TESTDATA / "core-variant"
    if sorted(path.name for path in variants.iterdir()) != sorted(name for name, _, refused in cases if not refused):
        fail(f"{variants} holds other folders than the variant runs")
    for name, config, refusal in cases:
        workspace = run.scratch / ("workspace-" + name)
        fill_workspace(run, workspace)
        core = workspace / CORE
        clear_tests(core)
        if config is not None:
            (core / "config.gno").write_text(config)
        if refusal:
            (core / "filetests/z_init_probe_filetest.gno").write_text(CORE_INIT_PROBE)
            require_refusal(name, run.test(core), refusal, "core")
            print(f"OK Core {name}", flush=True)
        else:
            variant_filetests(variants / name, core)
            test_package(run, core, f"Core {name}")


def vault_runs(run):
    """The vault's init under the configurations its main run can't use, with
    Core under its test configuration. init must refuse the committed fail-closed
    configuration, one for another network, and one whose Wormhole chain ID is
    not Core's."""
    cases = (("vault-committed-config-refused", None, "invalid-configuration"),
             ("vault-other-network-refused", vault_config(run, gno_chain="gnoland-1"), "wrong-network"),
             ("vault-core-mismatch-refused", vault_config(run, chain_id=258), "invalid-configuration"))
    for name, config, refusal in cases:
        workspace = run.scratch / ("workspace-" + name)
        fill_workspace(run, workspace)
        (workspace / CORE / "config.gno").write_text(core_config(run))
        vault = workspace / VAULT
        clear_tests(vault)
        if config is not None:
            (vault / "config.gno").write_text(config)
        (vault / "filetests/z_init_probe_filetest.gno").write_text(VAULT_INIT_PROBE)
        require_refusal(name, run.test(vault), refusal, "tokenbridge")
        print(f"OK vault {name}", flush=True)


def logic_limits_configs(run):
    """Each logic version of the limits variant, by path: small limits for GNOT and
    the corpus's allowlisted asset, which v2 makes exit-only under the same limits
    and v3 opens again under half the inbound budget."""
    allowlist = run.tb_corpus["allowlist"]
    per_transfer, outbound, inbound = SMALL_LIMITS
    return {LOGIC: logic_config(run, [(origin, SMALL_LIMITS) for origin in allowlist], SMALL_LIMITS),
            LOGIC_V2: logic_config(run, [(origin, SMALL_LIMITS, True) for origin in allowlist], SMALL_LIMITS),
            LOGIC_V3: logic_config(run, [(origin, (per_transfer, outbound, inbound // 2)) for origin in allowlist],
                                   SMALL_LIMITS)}


def logic_runs(run):
    """The logic under the configurations its main run can't use. init must
    refuse the committed fail-closed configuration and one allowlisting a gno
    token, while the vault's init passes in the same workspace, since the vault
    refuses with the same text. Under small limits the logic must pass the
    filetests of testdata/logic-variant/limits."""
    gno_token = no_limit_assets([f"{run.tb_corpus['chain_id']}:{run.tb_corpus['gnot_token_address']}"])
    cases = (("logic-committed-config-refused", {}, "invalid-configuration"),
             ("logic-gno-token-refused", {LOGIC: logic_config(run, gno_token)}, "invalid-configuration"),
             ("logic-limits", logic_limits_configs(run), None))
    variants = TESTDATA / "logic-variant"
    if sorted(path.name for path in variants.iterdir()) != ["limits"]:
        fail(f"{variants} holds other folders than the variant run limits")
    for name, configs, refusal in cases:
        workspace = run.scratch / ("workspace-" + name)
        fill_workspace(run, workspace)
        (workspace / CORE / "config.gno").write_text(core_config(run))
        (workspace / VAULT / "config.gno").write_text(vault_config(run))
        logic = workspace / LOGIC
        clear_tests(logic)
        for path, config in configs.items():
            if path == LOGIC:
                (logic / "config.gno").write_text(config)
            else:
                logic_copy(run, workspace, path, config)
        if refusal:
            (logic / "filetests/z_init_probe_filetest.gno").write_text(LOGIC_INIT_PROBE)
            vault = workspace / VAULT
            clear_tests(vault)
            (vault / "filetests/z_init_probe_filetest.gno").write_text(VAULT_INIT_PROBE)
            require_refusal(name, run.test(logic), refusal, "tokenbridge")
            vault_result = run.test(vault)
            if vault_result.returncode != 0 or not re.search(r"^--- PASS: \S*z_init_probe_filetest\.gno ",
                                                              vault_result.stdout, re.M):
                fail(f"{name}: the refusal may be the vault's, since its init failed too:\n{vault_result.stdout}")
            print(f"OK logic {name}", flush=True)
        else:
            variant_filetests(variants / "limits", logic)
            test_package(run, logic, name)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--keep", action="store_true", help="keep the scratch directory")
    opts = parser.parse_args()
    if not os.environ.get("GNOROOT"):
        fail("Set GNOROOT to a checkout of gno at the commit the Dockerfile pins")
    gnoroot = Path(os.environ["GNOROOT"]).resolve()
    gno = shutil.which(os.environ.get("GNO", "gno"))
    if not gno:
        fail("No gno binary: put gno on PATH or set GNO")
    scratch = Path(tempfile.mkdtemp(prefix="gno-realms-test-"))
    try:
        run = Run(gno, gnoroot, scratch)
        workspace = scratch / "workspace"
        realms = fill_workspace(run, workspace)
        require_test_only_imports(run, workspace, realms)
        prepare_core(run, workspace)
        (workspace / VAULT / "config.gno").write_text(vault_config(run))
        prepare_logic(run, workspace)
        for path in MODULES:
            test_package(run, workspace / path, path)
        core_runs(run)
        vault_runs(run)
        logic_runs(run)
        if any((run.home / "pkg" / "mod").glob("*")):
            fail(f"gno fetched packages into {run.home / 'pkg' / 'mod'}")
        print("PASS", flush=True)
    except BaseException:
        print(f"Scratch directory kept for inspection: {scratch}", file=sys.stderr, flush=True)
        raise
    if opts.keep:
        print(f"Scratch directory kept: {scratch}", flush=True)
    else:
        shutil.rmtree(scratch)


if __name__ == "__main__":
    try:
        main()
    except (Failure, corpus.CorpusError, OSError, subprocess.SubprocessError) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        sys.exit(1)
