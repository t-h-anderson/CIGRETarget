# Getting Started with the CIGRE Toolbox

This guide walks you through installing the CIGRE Toolbox, setting up your compiler, building your first CIGRE DLL, and importing CIGRE DLLs into Simulink.

---

## Contents

1. [Prerequisites](#1-prerequisites)
2. [Installing the Toolbox](#2-installing-the-toolbox)
3. [Registering a Compiler Toolchain](#3-registering-a-compiler-toolchain)
4. [Preparing a Simulink Model](#4-preparing-a-simulink-model)
5. [Checking the Model](#5-checking-the-model)
6. [Building a CIGRE DLL](#6-building-a-cigre-dll)
7. [Parameter Override](#7-parameter-override)
8. [Importing a CIGRE DLL into Simulink](#8-importing-a-cigre-dll-into-simulink)
9. [Running a CIGRE DLL in MATLAB](#9-running-a-cigre-dll-in-matlab)

---

## 1. Prerequisites

Before starting, ensure the following are available:

- **MATLAB** R2020a or later
- **Simulink** and **Embedded Coder** (required for code generation)
- A supported C compiler for your platform:

  | Compiler | Notes |
  |---|---|
  | Visual Studio 2017, 2019, or 2022 | Community edition is sufficient |
  | MinGW-w64 | Free; install via the MATLAB Add-On Explorer |

To confirm MATLAB can find your compiler, run:

```matlab
mex -setup C
```

---

## 2. Installing the Toolbox

The CIGRE Toolbox is distributed as a MATLAB Toolbox file (`.mltbx`). Because this file is generated from the source project, you must create it before installing.

### 2.1 Generate the `.mltbx` file

1. In MATLAB, select **Open > Project** and open **`CIGRE.prj`** from the repository root.
2. Inside the project, open **`ToolboxPackagingConfiguration.prj`** (also in the repository root).
3. Click **Package**. MATLAB generates `CIGRE.mltbx` in the repository root folder.

### 2.2 Install the toolbox

4. Double-click **`CIGRE.mltbx`** in the MATLAB Current Folder browser (or from the File Explorer).
5. MATLAB opens an installation dialog — click **Install**.

### 2.3 Close the project

6. **Close the MATLAB project** (`CIGRE.prj`) before using the toolbox functions.

> **Important:** The toolbox must be installed and the project closed before running `cigre.install`, `cigre.buildDLL`, or any other `cigre.*` functions. Leaving the project open can shadow the installed toolbox.

---

## 3. Registering a Compiler Toolchain

CIGRE needs to know which compiler to use when building DLLs. Run `cigre.install` once per compiler you intend to use.

### Visual Studio

```matlab
cigre.install('Toolchain', 'Visual C++ 2017')
```

Replace `'Visual C++ 2017'` with the version you have installed:

| Visual Studio version | `Toolchain` argument |
|---|---|
| Visual Studio 2017 | `'Visual C++ 2017'` |
| Visual Studio 2019 | `'Visual C++ 2019'` |
| Visual Studio 2022 | `'Visual C++ 2022'` |

### MinGW

```matlab
cigre.install('Toolchain', 'MinGW')
```

### Registering a specific bit-width

By default, both 32-bit and 64-bit toolchain entries are registered. To register only one:

```matlab
cigre.install('Toolchain', 'MinGW', 'Type', '64')   % 64-bit only
cigre.install('Toolchain', 'MinGW', 'Type', '32')   % 32-bit only
```

> **Note:** Earlier documentation referred to a `'VSVersion'` argument — this is incorrect. The current parameter name is `'Toolchain'`.

---

## 4. Preparing a Simulink Model

Before building a CIGRE DLL, your Simulink model must target the CIGRE code generation framework.

1. Open your model in Simulink.
2. Go to **Modeling > Model Settings** (or press **Ctrl+E**).
3. Select **Code Generation** in the left panel.
4. Set **System target file** to `cigre.tlc`.
5. Click **Apply** and close Model Settings.

The model must use a **fixed-step** solver. Configure this under **Solver** in Model Settings.

---

## 5. Checking the Model

Run the CIGRE Model Advisor checks to verify that your model conforms to the CIGRE requirements:

```matlab
cigre.checkModel('MyModel')
```

A report opens showing which checks pass or fail. Address any failures before proceeding to build. Common issues include incorrect interface types, virtual bus usage, or missing trigger subsystems.

---

## 6. Building a CIGRE DLL

### Basic build

```matlab
[desc, dll] = cigre.buildDLL('MyModel')
```

This generates `MyModel_CIGRE.dll` (and an associated `.h` header) in the current Simulink code generation folder.

| Return value | Description |
|---|---|
| `desc` | A `ModelDescription` object describing the model interface |
| `dll` | The DLL name (without `.dll` extension) |

### Specifying an output folder

```matlab
cigre.buildDLL('MyModel', 'CodeGenFolder', 'C:\output\MyModel')
```

### Generating code without compiling

Use `SkipBuild` to run only the code generation step (useful with Visual Studio manual builds or CI pipelines that compile separately):

```matlab
cigre.buildDLL('MyModel', 'SkipBuild', true)
```

### Bus signal handling

When the model has bus signals on its interface, use `BusAs` to control how they are flattened:

```matlab
cigre.buildDLL('MyModel', 'BusAs', 'Vector')   % default — flatten to vector
cigre.buildDLL('MyModel', 'BusAs', 'Ports')    % one port per bus element
```

### Preserving the wrapper model

By default the intermediate wrapper model (used to flatten buses) is deleted after the build. To keep it:

```matlab
cigre.buildDLL('MyModel', 'PreserveWrapper', true)
```

---

## 7. Parameter Override

By default, every tunable Simulink parameter in the model is exposed as a CIGRE parameter in the DLL interface. The **Parameter Override** feature lets you:

- **Hide** specific parameters from the CIGRE interface (they are hard-coded inside the DLL at their default value)
- **Override** the default value of any parameter

### Creating a parameter configuration file

Create a spreadsheet (`.xlsx`) with the following columns:

| Column | Type | Description |
|---|---|---|
| `Name` | text | Simulink parameter name (exact match required) |
| `IsVisible` | 0 or 1 | `1` = expose in CIGRE interface; `0` = hard-code inside DLL |
| `OverrideDefault` | number | *(optional)* Replace the model's default value |

**Example `ParameterConfig.xlsx`:**

| Name | IsVisible | OverrideDefault |
|---|---|---|
| Kp | 1 | |
| Ki | 1 | 2.5 |
| InternalGain | 0 | 100.0 |
| DeadBand | 0 | |

In this example:
- `Kp` is visible with its model default
- `Ki` is visible with its default overridden to `2.5`
- `InternalGain` is hidden and hard-coded as `100.0` inside the DLL
- `DeadBand` is hidden using the value from the model

Parameters that do not appear in the spreadsheet are treated as **visible** with their model defaults.

### Passing the configuration file to `buildDLL`

```matlab
cigre.buildDLL('MyModel', 'ParameterConfigFile', 'ParameterConfig.xlsx')
```

Place the `.xlsx` file alongside the model or provide an absolute path.

---

## 8. Importing a CIGRE DLL into Simulink

`cigre.importDLL` reads the metadata from any IEEE CIGRE-compliant DLL and creates a Simulink model containing a pre-configured block.

### Basic import

```matlab
modelPath = cigre.importDLL('MyController.dll')
```

MATLAB reads the DLL's `Model_GetInfo()` function to discover:
- Model name, version, and description
- Input and output port count, names, data types, and widths
- Fixed-step sample time
- Parameter names, default values, units, and groups

A Simulink model is created and opened automatically.

### Specifying options

```matlab
modelPath = cigre.importDLL('MyController.dll', ...
    'Header',       'C:\dlls\MyController.h', ...
    'OutputFolder', 'C:\models',              ...
    'BlockName',    'MyControllerBlock',       ...
    'OpenModel',    false)
```

| Option | Default | Description |
|---|---|---|
| `Header` | Same-named `.h` next to DLL | Path to the DLL header file |
| `OutputFolder` | Current directory | Where the generated `.slx` is saved |
| `BlockName` | Derived from DLL `ModelName` | Name for the block and the Simulink model |
| `OpenModel` | `true` | Open the model in Simulink after creation |

### What the generated block contains

- **Named input ports** — one per CIGRE input, labelled with the signal name
- **Named output ports** — one per CIGRE output, labelled with the signal name
- **Mask parameters** — one editable field per CIGRE parameter, with units and default values pre-filled
- **Hidden DLL/header paths** — stored in the mask so the S-Function can reload the library at simulation time

To use the block, open the generated model and connect it into your system-level diagram.

---

## 9. Running a CIGRE DLL in MATLAB

For testing or scripted validation outside of Simulink, use the `cigre.dll` classes directly.

```matlab
% Load the DLL
dll = cigre.dll.CigreDLL('MyModel_CIGRE');
cleanObj = dll.load();   % cleanObj unloads the DLL when it goes out of scope

% Create an interface instance with input data, output structure, and parameters
params = struct('Name', {'Kp', 'Ki'}, 'Value', {1.0, 0.5});
instance = cigre.dll.InterfaceInstance(inputCell, outputStruct, params);

% Initialise and step
dll.initialise(instance);
result = dll.run(instance, 'NSteps', 10);
```

See the test file `test/+test/+system/tGenerateCigre.m` for a complete example.

---

## Summary of API

| Function | Description |
|---|---|
| `cigre.install('Toolchain', name)` | Register a compiler toolchain (run once) |
| `cigre.checkModel(model)` | Run CIGRE compliance checks via Model Advisor |
| `cigre.buildDLL(model, ...)` | Generate a CIGRE-compliant DLL from a Simulink model |
| `cigre.importDLL(dllPath, ...)` | Import a CIGRE DLL as a Simulink block |

---

## See Also

- `doc/Quick Start Guide.md` — condensed one-page reference
- `doc/IEEE CIGRE DLL Documentation.pdf` — the IEEE CIGRE DLL interface specification
