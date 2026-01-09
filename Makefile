CC = gcc
CFLAGS = -Wall -Wextra -std=c11
TARGET = processus
SRC_DIR = src
SRC = $(SRC_DIR)/processus.c
RUBY_SCRIPT = $(SRC_DIR)/analyse_processus.rb

all: $(TARGET)

$(TARGET): $(SRC)
	$(CC) $(CFLAGS) -o $(TARGET) $(SRC)

clean:
	rm -f $(TARGET)

run: $(TARGET)
	./$(TARGET)

# Analyse d'un processus avec un script Ruby
analyse:
	@if [ -z "$(PID)" ]; then \
		echo "Usage: make analyse PID=<numéro>"; \
		exit 1; \
	fi
	ruby $(RUBY_SCRIPT) $(PID)

# Rendre le script Ruby exécutable
setup:
	chmod +x $(RUBY_SCRIPT)

.PHONY: all clean run analyse setup
