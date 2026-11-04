#include <stdio.h>
#include <string.h>
#include "cooling_controller.h"

typedef struct
{
    uint8_t pwm_duty_pct;
    bool fault_led_on;
} SimHardwareState;

static void sim_set_fan_pwm(uint8_t duty_pct, void *user_ctx)
{
    SimHardwareState *hw = (SimHardwareState *)user_ctx;
    if (hw != NULL)
    {
        hw->pwm_duty_pct = duty_pct;
    }
}

static void sim_set_fault_led(bool fault_active, void *user_ctx)
{
    SimHardwareState *hw = (SimHardwareState *)user_ctx;
    if (hw != NULL)
    {
        hw->fault_led_on = fault_active;
    }
}

static const char *sensor_status_label(int16_t temp_c, bool sensor_ok)
{
    if (!sensor_ok)
    {
        return "SIG_ERR";
    }
    if (temp_c < COOLING_SENSOR_MIN_C || temp_c > COOLING_SENSOR_MAX_C)
    {
        return "RNG_ERR";
    }
    return "OK";
}

int main(int argc, const char *const argv[])
{
    FILE *csv = NULL;

    if (argc != 1)
    {
        if (argc != 3 || strcmp(argv[1], "--csv") != 0)
        {
            fprintf(stderr, "Usage: %s [--csv output_file.csv]\n", argv[0]);
            return 1;
        }

        csv = fopen(argv[2], "w");
        if (csv == NULL)
        {
            perror("Could not open CSV output file");
            return 1;
        }

        fprintf(csv, "step,heat_rate_c_per_step,plant_temp_c,measured_temp_c,"
                     "signal_valid,fan_state,pwm_pct,sensor_fault,fault_led,valid_streak\n");
    }

    CoolingConfig config = {
        .low_on_c = 100,
        .low_off_c = 95,
        .high_on_c = 110,
        .high_off_c = 105};

    SimHardwareState hw_state = {
        .pwm_duty_pct = 0U,
        .fault_led_on = false};

    CoolingHal hal = {
        .set_fan_pwm = sim_set_fan_pwm,
        .set_fault_led = sim_set_fault_led,
        .user_ctx = &hw_state};

    CoolingController controller;

    if (cooling_init(&controller, &config) != COOLING_OK)
    {
        fprintf(stderr, "Failed to initialize controller\n");
        if (csv != NULL)
        {
            fclose(csv);
        }
        return 1;
    }

    if (cooling_set_hal(&controller, &hal) != COOLING_OK)
    {
        fprintf(stderr, "Failed to install HAL callbacks\n");
        if (csv != NULL)
        {
            fclose(csv);
        }
        return 1;
    }

    double plant_temp_c = 88.0;

    printf("Step | Load (C/s) | Temp (C) | Sensor  | Fan State | PWM  | Fault LED\n");
    printf("-----+------------+----------+---------+-----------+------+----------\n");

    for (int step = 1; step <= 20; step++)
    {
        double heat_rate = 2.5;
        bool sensor_ok = true;

        if (step >= 7 && step <= 11)
        {
            heat_rate = 4.0;
        }
        else if (step >= 15)
        {
            heat_rate = 0.8;
        }

        double cooling_rate = 0.0;

        if (cooling_get_state(&controller) == FAN_LOW)
        {
            cooling_rate = 2.2;
        }
        else if (cooling_get_state(&controller) == FAN_HIGH)
        {
            cooling_rate = 4.8;
        }

        plant_temp_c += (heat_rate - cooling_rate);

        int16_t measured_temp = (int16_t)(plant_temp_c + 0.5);

        if (step == 12)
        {
            sensor_ok = false;
        }
        else if (step == 13)
        {
            measured_temp = 185;
        }

        FanState state = cooling_update(&controller, measured_temp, sensor_ok);

        printf("%4d | %10.1f | %8d | %-7s | %-9s | %3u%% | %s\n",
               step,
               heat_rate,
               measured_temp,
               sensor_status_label(measured_temp, sensor_ok),
               cooling_state_name(state),
               (unsigned int)hw_state.pwm_duty_pct,
               hw_state.fault_led_on ? "ON" : "OFF");

        if (csv != NULL)
        {
            if (fprintf(csv, "%d,%.2f,%.2f,%d,%d,%d,%u,%d,%d,%u\n",
                        step,
                        heat_rate,
                        plant_temp_c,
                        (int)measured_temp,
                        sensor_ok ? 1 : 0,
                        (int)state,
                        (unsigned int)hw_state.pwm_duty_pct,
                        controller.sensor_fault ? 1 : 0,
                        hw_state.fault_led_on ? 1 : 0,
                        (unsigned int)controller.valid_streak) < 0)
            {
                perror("Could not write CSV trace");
                fclose(csv);
                return 1;
            }
        }
    }

    if (csv != NULL)
    {
        if (fclose(csv) != 0)
        {
            perror("Could not close CSV trace");
            return 1;
        }

        printf("CSV trace written to %s\n", argv[2]);
    }

    return 0;
}