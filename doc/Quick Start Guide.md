# CIGRE Toolbox — Quick Start Guide

## Prerequisites

- MATLAB R2020a or later with Simulink and Embedded Coder
- A supported C compiler:
  - **Windows**: Visual Studio 2017, 2019, or 2022 **or** MinGW-w64
  - Verify with `mex -setup C` in MATLAB

---

## Step 1 — Install the Toolbox

1. In the repository, open the `releases/` folder
2. Double-click the latest **`.mltbx`** file (e.g. `Simulink to CIGRE Export Tool 2.0.mltbx`) inside MATLAB to install
3. Click **Install** in the installation dialog

---

## Step 2 — Register Your Compiler

Run one of the following in the MATLAB Command Window:

```matlab
% Visual Studio
cigre.install(Toolchain="Visual C++ 2017")   % or 2019 / 2022

% MinGW
cigre.install(Toolchain="MinGW")
```

> To register only 64-bit: add `Type="64"` to the call.

---

## Step 3 — Prepare Your Simulink Model

1. Open your Simulink model
2. Go to **Modeling > Model Settings > Code Generation**
3. Set **System target file** to `cigre.tlc`
4. (Optional, requires **Simulink Check**) Run the CIGRE compliance check:

```matlab
cigre.checkModel("MyModel")
```

---

## Step 4 — Build the CIGRE DLL

```matlab
[desc, dll] = cigre.buildDLL("MyModel")
```

On success, `MyModel_CIGRE.dll` appears in the code generation folder.

### Common Options

```matlab
% Specify an output folder
cigre.buildDLL("MyModel", CodeGenFolder="C:\output")

% Generate code only (no compile step)
cigre.buildDLL("MyModel", SkipBuild=true)

% Control parameter visibility
cigre.buildDLL("MyModel", ParameterConfigFile="ParameterConfig.xlsx")
```

---

## Step 5 — (Optional) Import a CIGRE DLL into Simulink (Prototype)

*Note*: This is a prototype under development so may be unstable.

```matlab
cigre.importDLL("MyController.dll")
```

This generates a Simulink model with a masked block that wraps the DLL. Inputs, outputs, and parameters are configured automatically from the DLL metadata.

---

## Parameter Configuration Spreadsheet

Create `ParameterConfig.xlsx` to control which model parameters are exposed in the CIGRE interface:

| Name | IsVisible | OverrideDefault |
|---|---|---|
| Kp | 1 | *(blank = keep model default)* |
| Ki | 1 | 2.5 |
| InternalGain | 0 | 100.0 |

- `IsVisible = 0` hard-codes the parameter inside the DLL (not tunable at runtime)
- `OverrideDefault` replaces the model's default value when the DLL is built
- Parameters absent from the spreadsheet are visible with default values taken from Simulink

---

## Toolchain Reference

| Compiler | `Toolchain` argument |
|---|---|
| Visual Studio 2017 | `"Visual C++ 2017"` |
| Visual Studio 2019 | `"Visual C++ 2019"` |
| Visual Studio 2022 | `"Visual C++ 2022"` |
| MinGW-w64 | `"MinGW"` |

---

## Troubleshooting

| Problem | Solution |
|---|---|
| `mltbx` file not found | Check the `releases/` folder in the repository root |
| `cigre.install` fails | Run `mex -setup C` and confirm your compiler is installed |
| `cigre.tlc` target missing | Toolbox must be installed and project must be closed before building |
| MEX compile error on first `importDLL` | Run `mex -setup C` to configure a C compiler for MEX |
