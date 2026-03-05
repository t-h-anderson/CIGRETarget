# CIGRE Toolbox for MATLAB/Simulink

The CIGRE Toolbox generates IEEE CIGRE-compliant DLLs from Simulink models and imports CIGRE DLLs back into Simulink as reusable blocks. It targets the IEEE CIGRE DLL interface standard used for interoperability in power system simulation tools.

## Quick Start

### 1. Install the Toolbox

Open MATLAB and load the project:

```
Open CIGRE.prj
```

Generate the toolbox installer:

```
Open ToolboxPackagingConfiguration.prj
```

Click **Package** to produce `CIGRE.mltbx`, then double-click the `.mltbx` file inside MATLAB to install the toolbox. After installation, close the MATLAB project before using the toolbox.

### 2. Install the Build Toolchain

After installing the toolbox, register a compiler toolchain with CIGRE. Pass the `Toolchain` name-value argument matching your installed compiler:

**Visual Studio (2017, 2019, or 2022):**
```matlab
cigre.install('Toolchain', 'Visual C++ 2017')
cigre.install('Toolchain', 'Visual C++ 2019')
cigre.install('Toolchain', 'Visual C++ 2022')
```

**MinGW:**
```matlab
cigre.install('Toolchain', 'MinGW')
```

By default, both 32-bit and 64-bit toolchains are registered. To register only one:
```matlab
cigre.install('Toolchain', 'MinGW', 'Type', '64')
```

### 3. Check Your Model

Before building, verify that your Simulink model meets the CIGRE requirements:

```matlab
cigre.checkModel('MyModel')
```

The model must use the `cigre.tlc` system target file (set in **Model Settings > Code Generation**).

### 4. Build a CIGRE DLL

```matlab
[desc, dll] = cigre.buildDLL('MyModel')
```

This generates a CIGRE-compliant DLL named `MyModel_CIGRE.dll` in the current code generation folder.

**Common options:**

| Option | Default | Description |
|---|---|---|
| `CodeGenFolder` | Simulink default | Output folder for generated files |
| `BusAs` | `"Vector"` | How bus signals are flattened (`"Ports"` or `"Vector"`) |
| `SkipBuild` | `false` | Generate code without compiling |
| `ParameterConfigFile` | *(none)* | Path to a parameter configuration spreadsheet |

### 5. Import a CIGRE DLL into Simulink

To use an existing CIGRE-compliant DLL as a Simulink block:

```matlab
cigre.importDLL('MyController.dll')
```

This creates a Simulink model containing a pre-configured block with inputs, outputs, and parameters automatically wired from the DLL metadata.

**Options:**

| Option | Description |
|---|---|
| `OutputFolder` | Where to save the generated `.slx` |
| `BlockName` | Override the auto-derived block name |
| `Header` | Path to the DLL header (defaults to same-named `.h` file) |
| `OpenModel` | Open the model after creation (default: `true`) |

---

## Features

### Parameter Override

When building a DLL, you can control which Simulink parameters appear in the CIGRE interface and override their default values using an Excel spreadsheet.

Create a file `ParameterConfig.xlsx` with the following columns:

| Name | IsVisible | OverrideDefault |
|---|---|---|
| Kp | 1 | *(leave blank to keep model default)* |
| Ki | 1 | 2.5 |
| InternalGain | 0 | 100.0 |

- **Name** – the Simulink parameter name (must match exactly)
- **IsVisible** – `1` to expose in the CIGRE interface, `0` to hard-code it inside the DLL
- **OverrideDefault** – optional value that replaces the model's default

Pass the file path when building:

```matlab
cigre.buildDLL('MyModel', 'ParameterConfigFile', 'ParameterConfig.xlsx')
```

Parameters absent from the spreadsheet are visible by default.

### CIGRE DLL Import

`cigre.importDLL` wraps any IEEE CIGRE-compliant DLL (built by this toolbox or a third party) as a Simulink block:

```matlab
% Basic import — opens the generated model automatically
modelPath = cigre.importDLL('C:\dlls\MyController.dll')

% Specify header and output folder
modelPath = cigre.importDLL('MyController.dll', ...
    'Header',       'C:\dlls\MyController.h', ...
    'OutputFolder', 'C:\models',              ...
    'OpenModel',    false)
```

The generated block includes:
- Named input and output ports derived from the DLL metadata
- An editable mask parameter for every CIGRE parameter (default values pre-filled)
- Hidden fields for the DLL and header paths so the block reloads the library automatically at simulation time

---

## API Reference

| Function | Description |
|---|---|
| `cigre.install('Toolchain', ...)` | Register a compiler toolchain |
| `cigre.checkModel(model)` | Run CIGRE Model Advisor checks |
| `cigre.buildDLL(model, ...)` | Build a CIGRE-compliant DLL from a Simulink model |
| `cigre.importDLL(dllPath, ...)` | Import a CIGRE DLL as a Simulink block |

---

## See Also

- `doc/Getting Started.md` – step-by-step installation and first build walkthrough
- `doc/Quick Start Guide.md` – condensed reference card
- `doc/IEEE CIGRE DLL Documentation.pdf` – IEEE CIGRE DLL interface specification
