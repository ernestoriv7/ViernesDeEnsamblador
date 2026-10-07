# ================================================================
# Battle City - Nivel 1 adaptado a una pantalla bitmap de 64x64
# Arquitectura: RISC-V (RARS)
#
# Configuracion sugerida del Bitmap Display:
#   Unit Width in Pixels:  8
#   Unit Height in Pixels: 8
#   Display Width:         64
#   Display Height:        64
#   Base address:          gp
#
# Controles:
#   W = arriba
#   S = abajo
#   A = izquierda
#   D = derecha
#   Espacio = disparar (un proyectil activo, de un pixel)
# Los disparos normales rompen ladrillos en franjas de 5x2 pixeles,
# no rompen acero y atraviesan agua. Perder la base termina la partida.
#
# Uso de la pila en este ejemplo autonomo de RARS:
#   Cada registro guardado ocupa 4 bytes. Se reserva solo lo utilizado,
#   sin relleno para la alineacion de 16 bytes exigida por la ABI estandar.
#   Antes de retornar se restauran los registros y se libera la reserva.
# ================================================================

.eqv KEY_INPUT_ADDRESS  0xFFFF0004
.eqv KEY_STATUS_ADDRESS 0xFFFF0000

# Caracteres ASCII en minuscula
.eqv ASCII_W 119
.eqv ASCII_S 115
.eqv ASCII_A 97
.eqv ASCII_D 100
.eqv ASCII_ESPACIO 32
.eqv PROYECTIL_INTERVALO_MS 40

# Dimensiones del framebuffer
.eqv SCREEN_WIDTH  64
.eqv SCREEN_HEIGHT 64

# Colores en formato 0x00RRGGBB
.eqv COLOR_BLANCO  0x00FFFFFF
.eqv COLOR_NEGRO   0x00000000
.eqv COLOR_ROJO    0x00FF0000
.eqv COLOR_AZUL    0x000000FF
.eqv COLOR_LADRILLO 0x00E86F00
.eqv COLOR_ACERO   0x00B0B0B0
.eqv COLOR_AGUA    0x000066CC
.eqv COLOR_BASE    0x00FFD000
.eqv COLOR_TANQUE_CUERPO 0x000000FF
.eqv COLOR_TANQUE_CANON  0x00FFFFFF
.eqv COLOR_TANQUE_ORUGA  0x00404040

# Tamano del tanque (5x5) y direcciones posibles
.eqv TANQUE_TAM   5
.eqv DIR_ARRIBA     0
.eqv DIR_ABAJO      1
.eqv DIR_IZQUIERDA  2
.eqv DIR_DERECHA    3

.data
.align 2

# Posicion (esquina superior izquierda) y direccion inicial del tanque
tank_x:   .word 30
tank_y:   .word 30
tank_dir: .word DIR_ARRIBA
proyectil_activo: .word 0
proyectil_x: .word 0
proyectil_y: .word 0
proyectil_dir: .word 0
proyectil_tiempo: .word 0
partida_terminada: .word 0
mensaje_derrota: .asciz "Base destruida. Fin de la partida.\n"
.align 2
# Terreno persistente: no incluye el tanque ni el proyectil.
mapa_terreno: .space 16384

# Cada entrada del nivel contiene cinco palabras:
#   x, y, color, ancho, alto
# Cada entrada ocupa 20 bytes.
nivel_1_bloques:
    # Parte superior: seis columnas
    .word 5,  5, COLOR_LADRILLO, 5, 22
    .word 15, 5, COLOR_LADRILLO, 5, 22
    .word 25, 5, COLOR_LADRILLO, 5, 17
    .word 35, 5, COLOR_LADRILLO, 5, 17
    .word 45, 5, COLOR_LADRILLO, 5, 22
    .word 55, 5, COLOR_LADRILLO, 5, 22

    # Acero central superior
    .word 30, 15, COLOR_ACERO, 5, 5

    # Dos bloques pequenos debajo de las columnas centrales
    .word 25, 27, COLOR_LADRILLO, 5, 5
    .word 35, 27, COLOR_LADRILLO, 5, 5

    # Franja horizontal central
    .word 0,  32, COLOR_ACERO, 5, 5
    .word 10, 32, COLOR_LADRILLO, 10, 5
    .word 44, 32, COLOR_LADRILLO, 10, 5
    .word 59, 32, COLOR_ACERO, 5, 5

    # Obstaculo central con forma de U
    .word 25, 37, COLOR_LADRILLO, 5, 5
    .word 35, 37, COLOR_LADRILLO, 5, 5
    .word 30, 39, COLOR_LADRILLO, 5, 3

    # Parte inferior
    .word 5,  42, COLOR_LADRILLO, 5, 17
    .word 15, 42, COLOR_LADRILLO, 5, 17
    .word 25, 42, COLOR_LADRILLO, 5, 10
    .word 35, 42, COLOR_LADRILLO, 5, 10
    .word 45, 42, COLOR_LADRILLO, 5, 17
    .word 55, 42, COLOR_LADRILLO, 5, 17

    # Proteccion de la base
    .word 27, 56, COLOR_LADRILLO, 10, 2
    .word 27, 58, COLOR_LADRILLO, 3, 6
    .word 34, 58, COLOR_LADRILLO, 3, 6

    # Cuerpo de la base
    .word 30, 58, COLOR_BASE, 4, 5
nivel_1_bloques_fin:

.text
.globl main

# ================================================================
# Programa principal
# ================================================================
main:
    # Limpiar la pantalla antes de pintar el nivel.
    jal limpiar_pantalla
    jal pintar_nivel_1
    jal guardar_terreno

    # Pintar el tanque en su posicion inicial.
    lw a0, tank_x
    lw a1, tank_y
    lw a2, tank_dir
    li a3, COLOR_TANQUE_CUERPO
    li a4, COLOR_TANQUE_CANON
    jal pintar_tanque

espera_teclado:
    lw t0, partida_terminada
    bnez t0, pausa_bucle
    jal actualizar_proyectil
    lw t0, partida_terminada
    bnez t0, pausa_bucle

    # Consultar el registro de estado del teclado.
    li t0, KEY_STATUS_ADDRESS
    lw t1, 0(t0)
    andi t1, t1, 1
    beqz t1, pausa_bucle

    li t0, KEY_INPUT_ADDRESS
    lw a0, 0(t0)
    li t1, ASCII_ESPACIO
    beq a0, t1, tecla_disparo
    jal mover_tanque
    j pausa_bucle

tecla_disparo:
    jal disparar

pausa_bucle:
    # Leer KEY_INPUT_ADDRESS consume la tecla; no borrar eventos nuevos.
    li a0, 1
    li a7, 32
    ecall
    j espera_teclado

# ================================================================
# Funcion: limpiar_pantalla
# Llena los 4096 pixeles del framebuffer con negro.
# ================================================================
limpiar_pantalla:
    mv t0, gp
    li t1, 4096
    li t2, COLOR_NEGRO

limpiar_pantalla_loop:
    sw t2, 0(t0)
    addi t0, t0, 4
    addi t1, t1, -1
    bnez t1, limpiar_pantalla_loop
    ret

# ================================================================
# Funcion: pintar_nivel_1
# Pinta el primer nivel de Battle City mediante una tabla de bloques.
# ================================================================
pintar_nivel_1:
    addi sp, sp, -12
    sw ra, 0(sp)
    sw s0, 4(sp)
    sw s1, 8(sp)

    la s0, nivel_1_bloques
    la s1, nivel_1_bloques_fin

pintar_nivel_1_loop:
    bgeu s0, s1, pintar_nivel_1_detalles

    lw a0, 0(s0)       # x
    lw a1, 4(s0)       # y
    lw a2, 8(s0)       # color
    lw a3, 12(s0)      # ancho
    lw a4, 16(s0)      # alto
    jal pintar_bloque

    addi s0, s0, 20
    j pintar_nivel_1_loop

pintar_nivel_1_detalles:
    # Detalles blancos del emblema de la base.
    li a0, 30
    li a1, 59
    li a2, COLOR_BLANCO
    jal pintar_pixel

    li a0, 33
    li a1, 59
    li a2, COLOR_BLANCO
    jal pintar_pixel

    li a0, 31
    li a1, 60
    li a2, COLOR_BLANCO
    jal pintar_pixel

    li a0, 32
    li a1, 60
    li a2, COLOR_BLANCO
    jal pintar_pixel

    li a0, 31
    li a1, 61
    li a2, COLOR_BLANCO
    jal pintar_pixel

    li a0, 32
    li a1, 61
    li a2, COLOR_BLANCO
    jal pintar_pixel

    lw s1, 8(sp) 
    lw s0, 4(sp)
    lw ra, 0(sp)
    addi sp, sp, 12
    ret

# ================================================================
# Funcion: mover_tanque
# Recibe en a0 W, A, S o D, gira el tanque y lo mueve un
# pixel si el bloque 5x5 de destino esta libre y dentro de pantalla.
# ================================================================
mover_tanque:
    # Reservar espacio para el estado temporal y los registros preservados.
    addi sp, sp, -24
    sw ra, 0(sp)
    sw s0, 4(sp)
    sw s1, 8(sp)
    sw s2, 12(sp)
    sw s3, 16(sp)
    sw s4, 20(sp)

    # Mantener el estado actual en registros guardados durante las llamadas.
    # s0/s1 = posicion, s2 = direccion, s3/s4 = destino candidato.
    lw s0, tank_x
    lw s1, tank_y
    lw s2, tank_dir

    # Leer la tecla y seleccionar una de las cuatro direcciones validas.
    mv t0, a0

    li t1, ASCII_W
    beq t0, t1, mover_tanque_arriba

    li t1, ASCII_S
    beq t0, t1, mover_tanque_abajo

    li t1, ASCII_A
    beq t0, t1, mover_tanque_izquierda

    li t1, ASCII_D
    beq t0, t1, mover_tanque_derecha

    # Una tecla desconocida no modifica ni redibuja el tanque.
    j mover_tanque_fin

mover_tanque_arriba:
    # Orientar hacia arriba y proponer una celda hacia el norte.
    li s2, DIR_ARRIBA
    mv s3, s0
    addi s4, s1, -1
    j mover_tanque_validar_destino

mover_tanque_abajo:
    # Orientar hacia abajo y proponer una celda hacia el sur.
    li s2, DIR_ABAJO
    mv s3, s0
    addi s4, s1, 1
    j mover_tanque_validar_destino

mover_tanque_izquierda:
    # Orientar hacia la izquierda y proponer una celda al oeste.
    li s2, DIR_IZQUIERDA
    addi s3, s0, -1
    mv s4, s1
    j mover_tanque_validar_destino

mover_tanque_derecha:
    # Orientar hacia la derecha y proponer una celda al este.
    li s2, DIR_DERECHA
    addi s3, s0, 1
    mv s4, s1

mover_tanque_validar_destino:
    # Quitar el sprite actual para que no colisione consigo mismo.
    mv a0, s0
    mv a1, s1
    jal restaurar_tanque

    # Comprobar que el bloque completo de 5x5 cabe y esta libre.
    mv a0, s3
    mv a1, s4
    li a2, TANQUE_TAM
    li a3, TANQUE_TAM
    jal verificar_colision_bloque
    bnez a0, mover_tanque_actualizar_estado

    # Confirmar la nueva posicion solo cuando el destino esta despejado.
    mv s0, s3
    mv s1, s4

mover_tanque_actualizar_estado:
    # Incluso bloqueado, conservar la direccion elegida para mostrar el giro.
    sw s0, tank_x, t0
    sw s1, tank_y, t0
    sw s2, tank_dir, t0

    # Dibujar el tanque en su posicion confirmada con su nueva orientacion.
    mv a0, s0
    mv a1, s1
    mv a2, s2
    li a3, COLOR_TANQUE_CUERPO
    li a4, COLOR_TANQUE_CANON
    jal pintar_tanque
    jal pintar_proyectil

mover_tanque_fin:
    # Restaurar el contexto del llamador y liberar la pila.
    lw s4, 20(sp)
    lw s3, 16(sp)
    lw s2, 12(sp)
    lw s1, 8(sp)
    lw s0, 4(sp)
    lw ra, 0(sp)
    addi sp, sp, 24
    ret

# ================================================================
# Terreno separado del framebuffer para conservar los huecos y evitar
# que los sprites se conviertan en obstaculos.
# ================================================================
guardar_terreno:
    mv t0, gp
    la t1, mapa_terreno
    li t2, 4096
guardar_terreno_loop:
    lw t3, 0(t0)
    sw t3, 0(t1)
    addi t0, t0, 4
    addi t1, t1, 4
    addi t2, t2, -1
    bnez t2, guardar_terreno_loop
    ret

# a0/a1 = x/y; a0 = direccion del pixel en el mapa.
calcular_posicion_terreno:
    slli t0, a1, 6
    add t0, t0, a0
    slli t0, t0, 2
    la a0, mapa_terreno
    add a0, a0, t0
    ret

# a0/a1 = x/y; a2 = color. Actualiza terreno y pantalla.
escribir_terreno:
    slli t0, a1, 6
    add t0, t0, a0
    slli t0, t0, 2
    la t1, mapa_terreno
    add t1, t1, t0
    sw a2, 0(t1)
    add t1, gp, t0
    sw a2, 0(t1)
    ret

# a0/a1 = posicion anterior del tanque.
restaurar_tanque:
    slli t0, a1, 6
    add t0, t0, a0
    slli t0, t0, 2
    la t1, mapa_terreno
    add t1, t1, t0
    add t0, gp, t0
    li t2, TANQUE_TAM
restaurar_tanque_fila:
    li t3, TANQUE_TAM
restaurar_tanque_columna:
    lw t4, 0(t1)
    sw t4, 0(t0)
    addi t0, t0, 4
    addi t1, t1, 4
    addi t3, t3, -1
    bnez t3, restaurar_tanque_columna
    addi t0, t0, 236
    addi t1, t1, 236
    addi t2, t2, -1
    bnez t2, restaurar_tanque_fila
    ret

repintar_tanque:
    addi sp, sp, -4
    sw ra, 0(sp)
    lw a0, tank_x
    lw a1, tank_y
    lw a2, tank_dir
    li a3, COLOR_TANQUE_CUERPO
    li a4, COLOR_TANQUE_CANON
    jal pintar_tanque
    lw ra, 0(sp)
    addi sp, sp, 4
    ret

# ================================================================
# Disparo: nace justo fuera del canon y conserva su direccion.
# ================================================================
disparar:
    lw t0, proyectil_activo
    bnez t0, disparar_fin

    addi sp, sp, -4
    sw ra, 0(sp)

    lw t0, tank_x
    lw t1, tank_y
    lw t2, tank_dir
    sw t2, proyectil_dir, t3
    li t3, DIR_ARRIBA
    beq t2, t3, disparar_arriba
    li t3, DIR_ABAJO
    beq t2, t3, disparar_abajo
    li t3, DIR_IZQUIERDA
    beq t2, t3, disparar_izquierda
    addi t0, t0, TANQUE_TAM
    addi t1, t1, 2
    j disparar_iniciar
disparar_arriba:
    addi t0, t0, 2
    addi t1, t1, -1
    j disparar_iniciar
disparar_abajo:
    addi t0, t0, 2
    addi t1, t1, TANQUE_TAM
    j disparar_iniciar
disparar_izquierda:
    addi t0, t0, -1
    addi t1, t1, 2

disparar_iniciar:
    sw t0, proyectil_x, t3
    sw t1, proyectil_y, t3
    li t0, 1
    sw t0, proyectil_activo, t3
    li a7, 30
    ecall
    sw a0, proyectil_tiempo, t3
    jal resolver_proyectil

    lw ra, 0(sp)
    addi sp, sp, 4

disparar_fin:
    ret

actualizar_proyectil:
    lw t0, proyectil_activo
    beqz t0, actualizar_proyectil_fin
    addi sp, sp, -4
    sw ra, 0(sp)
    li a7, 30
    ecall
    lw t0, proyectil_tiempo
    sub t0, a0, t0
    li t1, PROYECTIL_INTERVALO_MS
    bltu t0, t1, actualizar_proyectil_restaurar
    sw a0, proyectil_tiempo, t1

    lw a0, proyectil_x
    lw a1, proyectil_y
    jal calcular_posicion_terreno
    lw a2, 0(a0)
    lw a0, proyectil_x
    lw a1, proyectil_y
    jal pintar_pixel
    jal repintar_tanque

    lw t0, proyectil_x
    lw t1, proyectil_y
    lw t2, proyectil_dir
    li t3, DIR_ARRIBA
    beq t2, t3, proyectil_avanzar_arriba
    li t3, DIR_ABAJO
    beq t2, t3, proyectil_avanzar_abajo
    li t3, DIR_IZQUIERDA
    beq t2, t3, proyectil_avanzar_izquierda
    addi t0, t0, 1
    j proyectil_avanzar_guardar
proyectil_avanzar_arriba:
    addi t1, t1, -1
    j proyectil_avanzar_guardar
proyectil_avanzar_abajo:
    addi t1, t1, 1
    j proyectil_avanzar_guardar
proyectil_avanzar_izquierda:
    addi t0, t0, -1
proyectil_avanzar_guardar:
    sw t0, proyectil_x, t3
    sw t1, proyectil_y, t3
    jal resolver_proyectil
actualizar_proyectil_restaurar:
    lw ra, 0(sp)
    addi sp, sp, 4
actualizar_proyectil_fin:
    ret

# Comprueba cada pixel recorrido, incluida la salida del canon.
resolver_proyectil:
    addi sp, sp, -4
    sw ra, 0(sp)
    lw a0, proyectil_x
    lw a1, proyectil_y
    bltz a0, proyectil_desactivar
    bltz a1, proyectil_desactivar
    li t0, SCREEN_WIDTH
    bge a0, t0, proyectil_desactivar
    li t0, SCREEN_HEIGHT
    bge a1, t0, proyectil_desactivar

    # El emblema blanco tambien pertenece a la base.
    li t0, 30
    blt a0, t0, proyectil_comprobar_material
    li t0, 34
    bge a0, t0, proyectil_comprobar_material
    li t0, 58
    blt a1, t0, proyectil_comprobar_material
    li t0, 63
    blt a1, t0, proyectil_destruir_base
proyectil_comprobar_material:
    jal calcular_posicion_terreno
    lw t0, 0(a0)
    li t1, COLOR_LADRILLO
    beq t0, t1, proyectil_romper_ladrillo
    beqz t0, proyectil_libre
    li t1, COLOR_AGUA
    beq t0, t1, proyectil_libre
    j proyectil_desactivar
proyectil_romper_ladrillo:
    jal destruir_ladrillo
    j proyectil_desactivar
proyectil_destruir_base:
    li t0, 1
    sw t0, partida_terminada, t1
    li a0, 30
    li a1, 58
    li a2, COLOR_ROJO
    li a3, 4
    li a4, 5
    jal pintar_bloque
    la a0, mensaje_derrota
    li a7, 4
    ecall
proyectil_desactivar:
    sw zero, proyectil_activo, t0
    j resolver_proyectil_fin
proyectil_libre:
    jal pintar_proyectil
resolver_proyectil_fin:
    lw ra, 0(sp)
    addi sp, sp, 4
    ret

# Un pixel blanco; el tanque se dibuja por encima de su propio disparo.
pintar_proyectil:
    lw t0, proyectil_activo
    beqz t0, pintar_proyectil_fin
    lw a0, proyectil_x
    lw a1, proyectil_y
    lw t0, tank_x
    blt a0, t0, pintar_proyectil_visible
    addi t0, t0, TANQUE_TAM
    bge a0, t0, pintar_proyectil_visible
    lw t0, tank_y
    blt a1, t0, pintar_proyectil_visible
    addi t0, t0, TANQUE_TAM
    blt a1, t0, pintar_proyectil_fin
pintar_proyectil_visible:
    li a2, COLOR_BLANCO
    j pintar_pixel
pintar_proyectil_fin:
    ret

# Franja perpendicular de cinco pixeles y dos de profundidad.
# Solo borra ladrillo, nunca materiales vecinos ni la base.
destruir_ladrillo:
    addi sp, sp, -28
    sw ra, 0(sp)
    sw s0, 4(sp)
    sw s1, 8(sp)
    sw s2, 12(sp)
    sw s3, 16(sp)
    sw s4, 20(sp)
    sw s5, 24(sp)
    lw s0, proyectil_x
    lw s1, proyectil_y
    li s2, 5
    li s3, 2
    lw t0, proyectil_dir
    li t1, DIR_IZQUIERDA
    bge t0, t1, destruir_ladrillo_horizontal
    addi s0, s0, -2
    li t1, DIR_ARRIBA
    bne t0, t1, destruir_ladrillo_iniciar
    addi s1, s1, -1
    j destruir_ladrillo_iniciar
destruir_ladrillo_horizontal:
    li s2, 2
    li s3, 5
    addi s1, s1, -2
    li t1, DIR_IZQUIERDA
    bne t0, t1, destruir_ladrillo_iniciar
    addi s0, s0, -1
destruir_ladrillo_iniciar:
    li s4, 0
destruir_ladrillo_fila:
    li s5, 0
destruir_ladrillo_pixel:
    add a0, s0, s5
    add a1, s1, s4
    bltz a0, destruir_ladrillo_siguiente
    bltz a1, destruir_ladrillo_siguiente
    li t0, SCREEN_WIDTH
    bge a0, t0, destruir_ladrillo_siguiente
    li t0, SCREEN_HEIGHT
    bge a1, t0, destruir_ladrillo_siguiente
    jal calcular_posicion_terreno
    lw t0, 0(a0)
    li t1, COLOR_LADRILLO
    bne t0, t1, destruir_ladrillo_siguiente
    add a0, s0, s5
    add a1, s1, s4
    li a2, COLOR_NEGRO
    jal escribir_terreno
destruir_ladrillo_siguiente:
    addi s5, s5, 1
    blt s5, s2, destruir_ladrillo_pixel
    addi s4, s4, 1
    blt s4, s3, destruir_ladrillo_fila
    lw s5, 24(sp)
    lw s4, 20(sp)
    lw s3, 16(sp)
    lw s2, 12(sp)
    lw s1, 8(sp)
    lw s0, 4(sp)
    lw ra, 0(sp)
    addi sp, sp, 28
    ret

# ================================================================
# Funcion: pintar_pixel
# Parametros:
#   a0 = coordenada x
#   a1 = coordenada y
#   a2 = color
# ================================================================
pintar_pixel:
    addi sp, sp, -8
    sw ra, 0(sp)
    sw s0, 4(sp)

    mv s0, a2
    jal calcular_posicion_fb
    sw s0, 0(a0)

    lw s0, 4(sp)
    lw ra, 0(sp)
    addi sp, sp, 8
    ret

# ================================================================
# Funcion: pintar_tanque
# Dibuja orugas, casco y canon dentro de una huella de 5x5 pixeles.
# Parametros:
#   a0 = x de la esquina superior izquierda
#   a1 = y de la esquina superior izquierda
#   a2 = direccion (DIR_ARRIBA, DIR_ABAJO, DIR_IZQUIERDA o DIR_DERECHA)
#   a3 = color del cuerpo
#   a4 = color del canon
# ================================================================
pintar_tanque:
    addi sp, sp, -24
    sw ra, 0(sp)
    sw s0, 4(sp)
    sw s1, 8(sp)
    sw s2, 12(sp)
    sw s3, 16(sp)
    sw s4, 20(sp)

    mv s0, a0            # x
    mv s1, a1            # y
    mv s2, a2            # direccion
    mv s3, a3            # color cuerpo
    mv s4, a4            # color canon

    li t0, DIR_ARRIBA
    beq s2, t0, pintar_tanque_canon_arriba
    li t0, DIR_ABAJO
    beq s2, t0, pintar_tanque_canon_abajo
    li t0, DIR_IZQUIERDA
    beq s2, t0, pintar_tanque_canon_izquierda

    # Por descarte, DIR_DERECHA: orugas horizontales.
pintar_tanque_orugas_horizontales:
    mv a0, s0
    mv a1, s1
    li a2, COLOR_TANQUE_ORUGA
    li a3, TANQUE_TAM
    li a4, 1
    jal pintar_bloque

    mv a0, s0
    addi a1, s1, 4
    li a2, COLOR_TANQUE_ORUGA
    li a3, TANQUE_TAM
    li a4, 1
    jal pintar_bloque
    j pintar_tanque_casco

pintar_tanque_canon_arriba:
    # Orugas verticales a ambos lados.
    mv a0, s0
    mv a1, s1
    li a2, COLOR_TANQUE_ORUGA
    li a3, 1
    li a4, TANQUE_TAM
    jal pintar_bloque

    addi a0, s0, 4
    mv a1, s1
    li a2, COLOR_TANQUE_ORUGA
    li a3, 1
    li a4, TANQUE_TAM
    jal pintar_bloque
    j pintar_tanque_casco

pintar_tanque_canon_abajo:
    # Orugas verticales a ambos lados.
    mv a0, s0
    mv a1, s1
    li a2, COLOR_TANQUE_ORUGA
    li a3, 1
    li a4, TANQUE_TAM
    jal pintar_bloque

    addi a0, s0, 4
    mv a1, s1
    li a2, COLOR_TANQUE_ORUGA
    li a3, 1
    li a4, TANQUE_TAM
    jal pintar_bloque
    j pintar_tanque_casco

pintar_tanque_canon_izquierda:
    # Orugas horizontales arriba y abajo.
    j pintar_tanque_orugas_horizontales

pintar_tanque_casco:
    addi a0, s0, 1
    addi a1, s1, 1
    mv a2, s3
    li a3, 3
    li a4, 3
    jal pintar_bloque

    li t0, DIR_ARRIBA
    beq s2, t0, pintar_tanque_canon_arriba_pintar
    li t0, DIR_ABAJO
    beq s2, t0, pintar_tanque_canon_abajo_pintar
    li t0, DIR_IZQUIERDA
    beq s2, t0, pintar_tanque_canon_izquierda_pintar

    # Cañon hacia la derecha.
    addi a0, s0, 2
    addi a1, s1, 2
    mv a2, s4
    li a3, 3
    li a4, 1
    jal pintar_bloque
    j pintar_tanque_fin

pintar_tanque_canon_arriba_pintar:
    addi a0, s0, 2
    mv a1, s1
    mv a2, s4
    li a3, 1
    li a4, 3
    jal pintar_bloque
    j pintar_tanque_fin

pintar_tanque_canon_abajo_pintar:
    addi a0, s0, 2
    addi a1, s1, 2
    mv a2, s4
    li a3, 1
    li a4, 3
    jal pintar_bloque
    j pintar_tanque_fin

pintar_tanque_canon_izquierda_pintar:
    mv a0, s0
    addi a1, s1, 2
    mv a2, s4
    li a3, 3
    li a4, 1
    jal pintar_bloque

pintar_tanque_fin:
    lw s4, 20(sp)
    lw s3, 16(sp)
    lw s2, 12(sp)
    lw s1, 8(sp)
    lw s0, 4(sp)
    lw ra, 0(sp)
    addi sp, sp, 24
    ret

# ================================================================
# Funcion: pintar_bloque
# Parametros:
#   a0 = x de la esquina superior izquierda
#   a1 = y de la esquina superior izquierda
#   a2 = color
#   a3 = ancho en pixeles
#   a4 = alto en pixeles
# ================================================================
pintar_bloque:
    addi sp, sp, -24
    sw ra, 0(sp)
    sw s0, 4(sp)
    sw s1, 8(sp)
    sw s2, 12(sp)
    sw s3, 16(sp)
    sw s4, 20(sp)

    mv s0, a0
    mv s1, a1
    mv s2, a2
    mv s3, a3
    mv s4, a4

pintar_bloque_loop:
    beqz s4, pintar_bloque_fin

    mv a0, s0
    mv a1, s1
    mv a2, s2
    mv a3, s3
    jal pintar_linea_horizontal

    addi s1, s1, 1
    addi s4, s4, -1
    j pintar_bloque_loop

pintar_bloque_fin:
    lw s4, 20(sp)
    lw s3, 16(sp)
    lw s2, 12(sp)
    lw s1, 8(sp)
    lw s0, 4(sp)
    lw ra, 0(sp)
    addi sp, sp, 24
    ret

# ================================================================
# Funcion: pintar_linea_horizontal
# Parametros:
#   a0 = x inicial
#   a1 = y
#   a2 = color
#   a3 = cantidad de pixeles
# ================================================================
pintar_linea_horizontal:
    addi sp, sp, -20
    sw ra, 0(sp)
    sw s0, 4(sp)
    sw s1, 8(sp)
    sw s2, 12(sp)
    sw s3, 16(sp)

    mv s0, a0
    mv s1, a1
    mv s2, a2
    mv s3, a3

pintar_linea_horizontal_loop:
    beqz s3, pintar_linea_horizontal_fin

    mv a0, s0
    mv a1, s1
    mv a2, s2
    jal pintar_pixel

    addi s0, s0, 1
    addi s3, s3, -1
    j pintar_linea_horizontal_loop

pintar_linea_horizontal_fin:
    lw s3, 16(sp)
    lw s2, 12(sp)
    lw s1, 8(sp)
    lw s0, 4(sp)
    lw ra, 0(sp)
    addi sp, sp, 20
    ret

# ================================================================
# Funcion: pintar_linea_vertical
# Parametros:
#   a0 = x
#   a1 = y inicial
#   a2 = color
#   a3 = cantidad de pixeles
# ================================================================
pintar_linea_vertical:
    addi sp, sp, -20
    sw ra, 0(sp)
    sw s0, 4(sp)
    sw s1, 8(sp)
    sw s2, 12(sp)
    sw s3, 16(sp)

    mv s0, a0
    mv s1, a1
    mv s2, a2
    mv s3, a3

pintar_linea_vertical_loop:
    beqz s3, pintar_linea_vertical_fin

    mv a0, s0
    mv a1, s1
    mv a2, s2
    jal pintar_pixel

    addi s1, s1, 1
    addi s3, s3, -1
    j pintar_linea_vertical_loop

pintar_linea_vertical_fin:
    lw s3, 16(sp)
    lw s2, 12(sp)
    lw s1, 8(sp)
    lw s0, 4(sp)
    lw ra, 0(sp)
    addi sp, sp, 20
    ret

# ================================================================
# Funcion: pintar_letra_e
# Parametros:
#   a0 = x
#   a1 = y
#   a2 = color
#   a3 = alto
# Conservada como utilidad del programa original.
# ================================================================
pintar_letra_e:
    addi sp, sp, -20
    sw ra, 0(sp)
    sw s0, 4(sp)
    sw s1, 8(sp)
    sw s2, 12(sp)
    sw s3, 16(sp)

    mv s0, a0
    mv s1, a1
    mv s2, a2
    mv s3, a3

    mv a0, s0
    mv a1, s1
    mv a2, s2
    mv a3, s3
    jal pintar_linea_vertical

    # Las tres barras horizontales tienen tres pixeles.
    mv a0, s0
    mv a1, s1
    mv a2, s2
    li a3, 3
    jal pintar_linea_horizontal

    srli t0, s3, 1
    mv a0, s0
    add a1, s1, t0
    mv a2, s2
    li a3, 3
    jal pintar_linea_horizontal

    mv a0, s0
    add a1, s1, s3
    addi a1, a1, -1
    mv a2, s2
    li a3, 3
    jal pintar_linea_horizontal

    lw s3, 16(sp)
    lw s2, 12(sp)
    lw s1, 8(sp)
    lw s0, 4(sp)
    lw ra, 0(sp)
    addi sp, sp, 20
    ret

# ================================================================
# Funcion: pintar_letra_a
# Parametros:
#   a0 = x
#   a1 = y
#   a2 = color
#   a3 = alto de las columnas
# Conservada como utilidad del programa original.
# ================================================================
pintar_letra_a:
    addi sp, sp, -20
    sw ra, 0(sp)
    sw s0, 4(sp)
    sw s1, 8(sp)
    sw s2, 12(sp)
    sw s3, 16(sp)

    mv s0, a0
    mv s1, a1
    mv s2, a2
    mv s3, a3

    addi a0, s0, 1
    addi a1, s1, 1
    mv a2, s2
    mv a3, s3
    jal pintar_linea_vertical

    addi a0, s0, 3
    addi a1, s1, 1
    mv a2, s2
    mv a3, s3
    jal pintar_linea_vertical

    addi a0, s0, 2
    mv a1, s1
    mv a2, s2
    jal pintar_pixel

    addi a0, s0, 1
    addi a1, s1, 3
    mv a2, s2
    li a3, 3
    jal pintar_linea_horizontal

    lw s3, 16(sp)
    lw s2, 12(sp)
    lw s1, 8(sp)
    lw s0, 4(sp)
    lw ra, 0(sp)
    addi sp, sp, 20
    ret

# ================================================================
# Funcion: calcular_posicion_fb
# Parametros:
#   a0 = x
#   a1 = y
# Retorno:
#   a0 = direccion del pixel en el framebuffer
# Formula: gp + ((y * 64 + x) * 4)
# ================================================================
calcular_posicion_fb:
    slli t0, a1, 6
    add t0, t0, a0
    slli t0, t0, 2
    add a0, gp, t0
    ret

# ================================================================
# Funcion: verificar_colision_bloque
# Parametros:
#   a0 = x de la esquina superior izquierda del bloque
#   a1 = y de la esquina superior izquierda del bloque
#   a2 = ancho del bloque
#   a3 = alto del bloque
# Retorno:
#   a0 = 0 si el bloque completo esta libre
#   a0 = 1 si algun pixel del bloque esta ocupado o fuera de pantalla
#
# Todo pixel del terreno diferente de negro se considera ocupado.
# ================================================================
verificar_colision_bloque:
    addi sp, sp, -24
    sw ra, 0(sp)
    sw s0, 4(sp)
    sw s1, 8(sp)
    sw s2, 12(sp)
    sw s3, 16(sp)
    sw s4, 20(sp)

    mv s0, a0            # x
    mv s1, a1            # y
    mv s2, a2            # ancho
    mv s3, a3            # alto

    # Limites izquierdo y superior.
    bltz s0, verificar_hay_colision
    bltz s1, verificar_hay_colision

    # Limites derecho e inferior.
    add t0, s0, s2
    li t1, SCREEN_WIDTH
    bgt t0, t1, verificar_hay_colision

    add t0, s1, s3
    li t1, SCREEN_HEIGHT
    bgt t0, t1, verificar_hay_colision

    li s4, 0             # fila actual

verificar_colision_bloque_filas:
    bge s4, s3, verificar_no_hay_colision

    li t3, 0             # columna actual

verificar_colision_bloque_columnas:
    bge t3, s2, verificar_colision_bloque_siguiente_fila

    add a0, s0, t3
    add a1, s1, s4
    jal calcular_posicion_terreno
    lw t1, 0(a0)
    bnez t1, verificar_hay_colision

    addi t3, t3, 1
    j verificar_colision_bloque_columnas

verificar_colision_bloque_siguiente_fila:
    addi s4, s4, 1
    j verificar_colision_bloque_filas

verificar_no_hay_colision:
    li a0, 0
    j verificar_colision_fin

verificar_hay_colision:
    li a0, 1

verificar_colision_fin:
    lw s4, 20(sp)
    lw s3, 16(sp)
    lw s2, 12(sp)
    lw s1, 8(sp)
    lw s0, 4(sp)
    lw ra, 0(sp)
    addi sp, sp, 24
    ret
