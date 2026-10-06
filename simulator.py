"""Synthetic benchmark generator for time-series causal discovery under latent confounding.

Every system is a stationary SVAR(1) with one shared latent AR(1) confounder::

    X_t = A @ X_{t-1} + B * L_t + eps_t,    eps_t ~ N(0, diag(sigma_eps^2))
    L_t = phi * L_{t-1} + eta_t,            eta_t ~ N(0, sigma_eta^2)

``A[i, j]`` is the lagged effect of variable ``j`` on variable ``i``.  ``B[i]`` is
the (contemporaneous) loading of the latent confounder on variable ``i``; two
variables with non-zero loadings are confounded.

Stationarity: the joint state (X, L) has a block-triangular transition matrix
[[A, B*phi], [0, phi]], so its spectral radius is max(rho(A), |phi|).  Both are
verified (and ``A`` is rescaled if needed) before simulating.

Outputs per system: ``df_full`` (observed + ``latent_*`` column, ground truth) and
``df_observed`` (latent dropped; the realistic input for causal discovery).
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Optional, Tuple

import numpy as np
import pandas as pd

T_DEFAULT = 5_000
SEED_DEFAULT = 42
BURN_IN = 500
MAX_RHO = 0.95  # A is rescaled if its spectral radius exceeds this


@dataclass(frozen=True)
class SystemSpec:
    """Parameters of one latent-confounded SVAR(1) system."""

    name: str
    variables: List[str]
    latent_name: str
    A: np.ndarray                 # (d, d) lagged coefficient matrix
    B: np.ndarray                 # (d,) latent loadings
    phi: float                    # latent AR coefficient
    sigma_eps: np.ndarray         # (d,) observation-innovation std devs
    sigma_eta: float = 1.0        # latent-innovation std dev
    edges_doc: Tuple[str, ...] = ()  # human-readable ground-truth description


# --------------------------------------------------------------------------- #
# Core utilities
# --------------------------------------------------------------------------- #
def spectral_radius(M: np.ndarray) -> float:
    """Return the spectral radius (max |eigenvalue|) of a square matrix."""
    return float(np.max(np.abs(np.linalg.eigvals(M))))


def ensure_stationary(A: np.ndarray, phi: float, max_rho: float = MAX_RHO) -> np.ndarray:
    """Validate |phi| < 1 and rescale ``A`` so that rho(A) <= ``max_rho`` < 1.

    Rescaling preserves the sparsity pattern (the causal graph).
    """
    if abs(phi) >= 1.0:
        raise ValueError(f"Latent AR coefficient must satisfy |phi| < 1, got {phi}.")
    rho = spectral_radius(A)
    if rho >= max_rho:
        A = A * (max_rho / rho)
    return A


def simulate_svar_latent(
    spec: SystemSpec, T: int = T_DEFAULT, seed: int = SEED_DEFAULT, burn_in: int = BURN_IN
) -> Tuple[pd.DataFrame, pd.DataFrame]:
    """Simulate a system and return ``(df_full, df_observed)``.

    Args:
        spec: System parameters.
        T: Number of retained timesteps.
        seed: Seed for ``numpy.random.default_rng``.
        burn_in: Initial steps discarded so the process is in its stationary regime.

    Returns:
        ``df_full`` with observed columns plus ``spec.latent_name``; ``df_observed``
        identical but with the latent column dropped.
    """
    A = ensure_stationary(np.asarray(spec.A, float), spec.phi)
    B = np.asarray(spec.B, float)
    d = len(spec.variables)
    rng = np.random.default_rng(seed)

    n = T + burn_in
    eps = rng.normal(0.0, 1.0, size=(n, d)) * spec.sigma_eps
    eta = rng.normal(0.0, spec.sigma_eta, size=n)

    X = np.zeros((n, d))
    L = np.zeros(n)
    for t in range(1, n):
        L[t] = spec.phi * L[t - 1] + eta[t]
        X[t] = A @ X[t - 1] + B * L[t] + eps[t]

    X, L = X[burn_in:], L[burn_in:]
    df_full = pd.DataFrame(X, columns=spec.variables)
    df_full[spec.latent_name] = L
    df_full.index.name = "t"
    df_observed = df_full.drop(columns=[spec.latent_name])
    return df_full, df_observed


def _build_A(variables: List[str], edges: Dict[Tuple[str, str], float]) -> np.ndarray:
    """Build A from ``{(cause, effect): coef}``; ``(v, v)`` entries are autoregressive."""
    idx = {v: i for i, v in enumerate(variables)}
    A = np.zeros((len(variables), len(variables)))
    for (cause, effect), w in edges.items():
        A[idx[effect], idx[cause]] = w
    return A


def _loadings(variables: List[str], loads: Dict[str, float]) -> np.ndarray:
    return np.array([loads.get(v, 0.0) for v in variables])


# --------------------------------------------------------------------------- #
# System definitions
# --------------------------------------------------------------------------- #
def gaming_spec() -> SystemSpec:
    """System 1: multiplayer mobile gaming (latent: viral stream / room raid)."""
    v = ["P", "Q", "ping", "F"]
    edges = {
        ("P", "P"): 0.6, ("Q", "Q"): 0.5, ("ping", "ping"): 0.55, ("F", "F"): 0.4,
        ("P", "Q"): 0.45,      # past player count -> matchmaking queue
        ("P", "F"): 0.25,      # player load -> frame drops
        ("ping", "F"): 0.30,   # high ping -> frame drops
    }
    return SystemSpec(
        name="gaming", variables=v, latent_name="latent_viral_surge",
        A=_build_A(v, edges), B=_loadings(v, {"P": 0.9, "ping": 0.7}), phi=0.85,
        sigma_eps=np.array([0.6, 0.5, 0.5, 0.5]),
        edges_doc=("P(t-1)->Q", "P(t-1)->F", "ping(t-1)->F", "L->P", "L->ping"),
    )


def crm_spec() -> SystemSpec:
    """System 2: enterprise CRM microservices (latent: hypervisor throttling)."""
    v = ["C", "D", "A", "E"]
    edges = {
        ("C", "C"): 0.6, ("D", "D"): 0.55, ("A", "A"): 0.5, ("E", "E"): 0.35,
        ("C", "A"): 0.35,      # CPU load -> API latency
        ("D", "A"): 0.30,      # DB queue depth -> API latency
        ("A", "E"): 0.45,      # API latency -> 504 timeouts
    }
    return SystemSpec(
        name="crm", variables=v, latent_name="latent_hypervisor_throttle",
        A=_build_A(v, edges), B=_loadings(v, {"C": 0.85, "D": 0.65}), phi=0.9,
        sigma_eps=np.array([0.5, 0.6, 0.5, 0.5]),
        edges_doc=("C(t-1)->A", "D(t-1)->A", "A(t-1)->E", "L->C", "L->D"),
    )


def campus_spec() -> SystemSpec:
    """System 3: smart campus grid (latent: auditorium symposium overrun)."""
    v = ["S", "W", "K", "H"]
    edges = {
        ("S", "S"): 0.5, ("W", "W"): 0.6, ("K", "K"): 0.55, ("H", "H"): 0.5,
        ("K", "S"): 0.40,      # cafeteria congestion -> shuttle delays
        ("W", "H"): 0.25,      # Wi-Fi density (occupancy) -> hall energy draw
    }
    return SystemSpec(
        name="campus", variables=v, latent_name="latent_symposium_overrun",
        A=_build_A(v, edges), B=_loadings(v, {"W": 0.9, "K": 0.8}), phi=0.8,
        sigma_eps=np.array([0.6, 0.5, 0.5, 0.5]),
        edges_doc=("K(t-1)->S", "W(t-1)->H", "L->W", "L->K"),
    )


# --------------------------------------------------------------------------- #
# Dedicated generation functions
# --------------------------------------------------------------------------- #
def generate_gaming_system(T: int = T_DEFAULT, seed: int = SEED_DEFAULT) -> Tuple[pd.DataFrame, pd.DataFrame]:
    """Generate System 1 (gaming). Returns ``(df_full, df_observed)``."""
    return simulate_svar_latent(gaming_spec(), T, seed)


def generate_crm_system(T: int = T_DEFAULT, seed: int = SEED_DEFAULT) -> Tuple[pd.DataFrame, pd.DataFrame]:
    """Generate System 2 (CRM microservices). Returns ``(df_full, df_observed)``."""
    return simulate_svar_latent(crm_spec(), T, seed)


def generate_campus_system(T: int = T_DEFAULT, seed: int = SEED_DEFAULT) -> Tuple[pd.DataFrame, pd.DataFrame]:
    """Generate System 3 (smart campus). Returns ``(df_full, df_observed)``."""
    return simulate_svar_latent(campus_spec(), T, seed)


# --------------------------------------------------------------------------- #
# Diagnostics
# --------------------------------------------------------------------------- #
def adf_summary(df: pd.DataFrame) -> Optional[Dict[str, float]]:
    """ADF p-values per column if ``statsmodels`` is installed, else ``None``."""
    try:
        from statsmodels.tsa.stattools import adfuller
    except ImportError:
        return None
    return {c: float(adfuller(df[c].to_numpy(), autolag="AIC")[1]) for c in df.columns}


def report(spec: SystemSpec, df_full: pd.DataFrame, df_obs: pd.DataFrame, outdir: Path) -> None:
    """Save CSVs and print statistics, stationarity checks, and file sizes."""
    print("=" * 78)
    print(f"SYSTEM: {spec.name}   (T={len(df_full)}, latent={spec.latent_name})")
    print("Ground-truth structure:", ", ".join(spec.edges_doc))
    print("-" * 78)
    print(df_full.describe().round(3).to_string())

    A_eff = ensure_stationary(spec.A, spec.phi)
    rho_a, rho_joint = spectral_radius(A_eff), max(spectral_radius(A_eff), abs(spec.phi))
    ok = rho_joint < 1.0
    print(f"\nStationarity: rho(A)={rho_a:.4f}, |phi|={abs(spec.phi):.2f}, "
          f"joint rho={rho_joint:.4f} -> {'PASS' if ok else 'FAIL'}")
    adf = adf_summary(df_full)
    if adf is None:
        print("ADF test: statsmodels not installed; eigenvalue check used.")
    else:
        print("ADF p-values (H0: unit root):",
              {k: round(p, 4) for k, p in adf.items()})

    for kind, df in (("full", df_full), ("observed", df_obs)):
        path = outdir / f"data_{spec.name}_{kind}.csv"
        df.to_csv(path)
        print(f"Saved {path.name}: {path.stat().st_size / 1024:.1f} KiB, "
              f"{df.shape[0]} rows x {df.shape[1]} cols")
    assert spec.latent_name not in df_obs.columns
    assert df_obs.equals(df_full.drop(columns=[spec.latent_name]))
    print()


if __name__ == "__main__":
    outdir = Path(__file__).resolve().parent
    runs = [
        (gaming_spec(), generate_gaming_system),
        (crm_spec(), generate_crm_system),
        (campus_spec(), generate_campus_system),
    ]
    for spec, gen in runs:
        df_full, df_obs = gen(T=T_DEFAULT, seed=SEED_DEFAULT)
        report(spec, df_full, df_obs, outdir)
