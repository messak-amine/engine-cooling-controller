# Engine Cooling Controller

A small **Embedded C** project that simulates an engine cooling fan controller on a PC. It uses a finite-state machine, temperature hysteresis, sensor-fault handling, and a hardware abstraction interface to command fan outputs.

The project is automotive-inspired, but it is **not firmware for a real ECU**. It demonstrates control logic and host-based, software-in-the-loop-style testing without a microcontroller or physical fan.

## Features

- Three fan states: `FAN_OFF`, `FAN_LOW`, and `FAN_HIGH`
- Configurable temperature thresholds, checked during initialization
- Two-stage hysteresis to avoid frequent fan switching
- Simulated PWM commands: **0%**, **50%**, and **100%**
- Hardware abstraction callbacks for fan PWM and a fault indicator
- Detection of invalid sensor signals and out-of-range readings
- HIGH fan fallback during sensor faults
- Recovery after **three consecutive valid readings**
- A simplified closed-loop thermal simulation and **10 automated C tests**
- GitHub Actions workflow for compilation, tests, and Cppcheck analysis

## Architecture

```text
Simulated thermal plant
         |
         v
Temperature + sensor validity
         |
         v
+------------------------------+
| Cooling controller (C)       |
| - configuration validation   |
| - state machine + hysteresis |
| - sensor fault / recovery    |
+------------------------------+
         |
         v
  HAL callbacks (mocked on PC)
         |
         +--> PWM command (0 / 50 / 100%)
         +--> Fault indicator (ON / OFF)
         |
         v
 Simulated cooling effect
         |
         +---- feedback to thermal plant
```

The controller is in `src/cooling_controller.c`. The PC simulation in `src/main.c` supplies temperatures and receives outputs through callback functions. This separation makes the control logic testable without hardware and allows a future target-specific driver to implement the same interface.

### Fan states and hysteresis

Default configuration:

| Transition | Temperature | PWM after transition |
|---|---:|---:|
| OFF → LOW | 100°C or higher | 50% |
| LOW → OFF | 95°C or lower | 0% |
| LOW → HIGH | 110°C or higher | 100% |
| HIGH → LOW | 105°C or lower | 50% |

The controller can also move directly from OFF to HIGH at 110°C or above, or from HIGH to OFF at 95°C or below. Because of hysteresis, a temperature alone does not always determine the state: the **previous state matters**.

The defaults are for demonstration. They are not calibrated for a particular vehicle.

### Configuration checks

`cooling_init()` rejects null arguments and threshold configurations that do not satisfy:

```text
low_off_c < low_on_c < high_off_c < high_on_c
```

It also requires the lowest OFF threshold to be above -40°C and the highest ON threshold to be below 150°C. A valid configuration initializes the controller in `FAN_OFF`.

### Sensor faults and recovery

A reading is considered invalid if `sensor_valid` is false or the measured temperature is outside **-40°C to 150°C** (inclusive).

On an invalid reading, the controller sets `sensor_fault`, resets its valid-reading counter, and commands `FAN_HIGH` (100% PWM). The fault indicator callback is set to ON when registered.

The fault clears only after **three consecutive valid updates**. At that point, the controller evaluates the normal hysteresis rules starting from HIGH:

| Temperature at recovery | Result |
|---|---|
| 95°C or below | OFF |
| Above 95°C through 105°C | LOW |
| Above 105°C | Remains HIGH |

A new invalid reading during recovery restarts the counter. The HIGH fallback is an educational policy, **not** a validated functional-safety mechanism.

### Closed-loop simulation

`src/main.c` runs a deterministic 20-step simulation. It changes a simplified heating rate, subtracts cooling based on the previous fan state, and feeds the resulting temperature back into the controller. It also injects a sensor signal fault and an out-of-range measurement.

The simulation prints the step, heating rate, measured temperature, sensor status, fan state, PWM command, and fault indicator. The thermal model is intentionally simple; it is not a physically calibrated engine model.

## MATLAB-based validation (R2024a)

The C simulation can export a 20-step trace for independent checking and
visualization in MATLAB. The C controller is unchanged; MATLAB serves as an
offline reference model, not as an ECU runtime component.

1. From **Git Bash** at the repository root, run `make trace`. This generates
   `results/cooling_trace.csv` (ignored by Git).
2. In **MATLAB**, change to the repository folder and run:

   ```matlab
   addpath('matlab')
   analyze_cooling
   ```

The MATLAB script reads the CSV, calculates a separate FSM/fault-recovery
reference, checks every recorded state and output, and saves a four-panel
figure to `results/cooling_analysis.png`. MATLAB R2024a is supported; no
Simulink or other add-on is required for this workflow.

The reference model checks the supplied 20-step test scenario, not all
possible input sequences. This is **offline cross-checking**, not real-time
co-simulation, hardware-in-the-loop testing, or functional-safety evidence.

### MATLAB validation results

The following plots show temperature evolution, injected sensor faults, PWM commands, and fault recovery.

![Engine Cooling Controller - MATLAB Validation](docs/cooling_analysis.png)

## Project structure

```text
.github/workflows/ci.yml       GitHub Actions workflow
include/cooling_controller.h   Public types and controller API
src/cooling_controller.c       State machine, fault logic, HAL outputs
src/main.c                     PC thermal simulation and mock hardware
tests/test_cooling_controller.c C assertion-based unit tests
Makefile                        Build and test commands
.gitignore                      Generated files excluded from Git
LICENSE                         MIT license
README.md                       Project documentation
```

## Build and run

**Requirements:** a C11-capable GCC compiler and GNU Make. No third-party C libraries or real hardware are required. The steps below were exercised on Windows using GCC and GNU Make through Git Bash.

From the project root:

```bash
make test   # Build and run the 10 unit tests
make sim    # Build and run the 20-step simulation
make clean  # Remove generated binaries and object files
```

Alternatively, compile the test executable directly:

```bash
gcc -std=c11 -Wall -Wextra -Werror -Iinclude \
  tests/test_cooling_controller.c src/cooling_controller.c -o cooling_tests
./cooling_tests
```

On Windows, the compiled executable can have an `.exe` suffix. The expected test summary is:

```text
All cooling controller unit tests passed (10/10).
```

## Automated tests

The project uses standard C `assert()` calls, with no external test framework.

| ID | Test function | Behavior checked |
|---|---|---|
| R1 | `test_config_validation` | Valid configuration, invalid threshold ordering, null arguments |
| R2 | `test_normal_operation` | Normal OFF / LOW / HIGH transitions |
| R3 | `test_low_hysteresis` | LOW-stage hysteresis |
| R4 | `test_high_hysteresis` | HIGH-stage hysteresis |
| R5 | `test_direct_high_activation` | Direct OFF → HIGH transition |
| R6 | `test_sensor_failure` | Invalid sensor signal and HIGH fallback |
| R7 | `test_invalid_temperature` | Values outside the valid sensor range |
| R8 | `test_fault_recovery` | Three valid readings and recovery across temperature bands |
| R9 | `test_interrupted_recovery` | Recovery counter resets after a new invalid reading |
| R10 | `test_state_getters_and_hal` | State accessors and mock PWM/fault callbacks |

The CI workflow runs the tests and simulation and performs Cppcheck static analysis on pushes to `main` and pull requests targeting `main`.

These tests check selected behaviors; they do not establish exhaustive coverage or functional-safety compliance.

## Limitations

This is a **PC-based educational simulation**, not a production-ready ECU implementation.

- No real temperature sensor, PWM peripheral, fan motor, or fault LED is connected.
- HAL callbacks only demonstrate a possible hardware interface; no MCU driver is provided.
- The thermal plant is simplified, with no calibrated physics or realistic sensor noise.
- Calls to `cooling_update()` are simulated steps, not a real-time scheduler with timing guarantees.
- No CAN communication, diagnostics protocol, or physical fan-failure monitoring is implemented.
- The project does not implement or claim AUTOSAR or ISO 26262 compliance.
