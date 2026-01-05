#define _DEFAULT_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <signal.h>
#include <string.h>

void infinite_loop() { // Etat R
    printf("Boucle infinie (Etat R). Ctrl+C pour arrêter.\n");
    while(1); 
}

void memory_leak() { // Etat S 
    printf("Fuite mémoire progressive (regardez RES/MEM%%)...\n");
    while(1) {
        char * bloc = (char*)malloc(1024 * 1024); // 1 Mo
        if(bloc) memset(bloc, 0, 1024 * 1024);    // Force l'allocation
        usleep(50000); // 50ms pause
    }
}

void IO_lock() { // Etat D
    printf("Parent (PID: %d) va passer en Etat D pendant 15s...\n", getpid());
    if (vfork() == 0) {
        sleep(15); 
        _exit(0);
    }
    printf("Parent libéré de l'état D.\n");
}

void make_zombie() { // Etat Z
    pid_t pid = fork();
    if (pid == 0) {
        exit(0); // l'enfant meurt -> Zombie
    } else {
        printf("Le fils est Zombie (Z). Vérifiez avec 'ps' maintenant !\n");
        printf("Le parent dort 20s...\n");
        sleep(20);
    }
}

void make_stopped() { // Etat T
    printf("Auto-stop (Etat T). Tapez 'kill -CONT %d' ailleurs pour continuer.\n", getpid());
    raise(SIGSTOP);
    printf("Reprise du processus !\n");
}

int main(int argc, char *argv[]) {
    if (argc != 2) {
        printf("Usage: %s <option>\n", argv[0]);
        printf("1 - Boucle CPU (R)\n");
        printf("2 - Fuite Mémoire (S)\n");
        printf("3 - Blocage I/O (D)\n");
        printf("4 - Zombie (Z)\n");
        printf("5 - Stoppé (T)\n");
        exit(EXIT_FAILURE);
        return 1;
    }

    int choix = atoi(argv[1]);

    switch(choix) {
        case 1: infinite_loop(); break;
        case 2: memory_leak(); break;
        case 3: IO_lock(); break;
        case 4: make_zombie(); break;
        case 5: make_stopped(); break;
        default: printf("Choix invalide.\n"); return 1;
    }

    return 0;
}