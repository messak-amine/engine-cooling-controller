.RECIPEPREFIX := >
ifeq ($(origin CC),default)
CC := gcc
endif
CFLAGS  := -std=c11 -Wall -Wextra -Werror -Iinclude

SRC     := src/cooling_controller.c
SIM_SRC := src/main.c
TST_SRC := tests/test_cooling_controller.c

SIM_BIN := cooling_sim
TST_BIN := cooling_tests

.PHONY: all sim test clean

all: $(SIM_BIN) $(TST_BIN)

$(SIM_BIN): $(SIM_SRC) $(SRC) include/cooling_controller.h
> $(CC) $(CFLAGS) $(SIM_SRC) $(SRC) -o $(SIM_BIN)

$(TST_BIN): $(TST_SRC) $(SRC) include/cooling_controller.h
> $(CC) $(CFLAGS) $(TST_SRC) $(SRC) -o $(TST_BIN)

sim: $(SIM_BIN)
> ./$(SIM_BIN)

test: $(TST_BIN)
> ./$(TST_BIN)

clean:
> rm -f $(SIM_BIN) $(TST_BIN) *.exe *.o *.obj *.gcda *.gcno *.gcov

# Export the deterministic C simulation as data for MATLAB.
.PHONY: trace
trace: $(SIM_BIN)
> mkdir -p results
> ./$(SIM_BIN) --csv results/cooling_trace.csv
