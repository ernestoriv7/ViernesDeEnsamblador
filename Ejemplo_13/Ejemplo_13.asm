# ================================================================
# Battle City - Nivel 
# Arquitectura: RISC-V (RARS)
#
# Configuracion sugerida del Bitmap Display:
#   Unit Width in Pixels:  8
#   Unit Height in Pixels: 8
#   Display Width:         512
#   Display Height:        512
#   Base address:          gp
#
# Para entradas usar Keyboard and Display MMIO Simulator
#
# Controles:
#   W = arriba
#   S = abajo
#   A = izquierda
#   D = derecha
# ================================================================

.eqv KEY_INPUT_ADDRESS 0xFFFF0004
.eqv KEY_STATUS_ADDRESS 0xFFFF0000
# Para referencia revisar https://www.it.uu.se/education/course/homepage/os/vt18/module-1/memory-mapped-io/

# Caracteres ASCII en minúscula
.eqv ASCII_W 119
.eqv ASCII_S 115
.eqv ASCII_A 97
.eqv ASCII_D 100

.eqv LETRA_E_X, 12
.eqv LETRA_E_Y, 16
.eqv LETRA_E_H, 4

.eqv LETRA_A_X, 32
.eqv LETRA_A_Y, 16
.eqv LETRA_A_H, 3

# Colores en formato 0x00RRGGBB
.eqv COLOR_BLANCO  0x00FFFFFF
.eqv COLOR_NEGRO   0x00000000
.eqv COLOR_ROJO    0x00FF0000
.eqv COLOR_AZUL    0x000000FF
.eqv COLOR_LADRILLO 0x00E86F00
.eqv COLOR_ACERO   0x00B0B0B0
.eqv COLOR_AGUA    0x000066CC
.eqv COLOR_BASE    0x00FFD000


.data
#color_blanco: .word 0x00FFFFFF #Blanco(R=FF, G=FF, B=FF)
#color_negro: .word 0x00000000 #Negro(R=00, G=00, B=00)
pixel_x: .word 32
pixel_y: .word 32

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
main:
	# Limpiar la pantalla antes de pintar el nivel.
    jal limpiar_pantalla
    jal pintar_nivel_1

    # Pintar el jugador en su posicion inicial.
    lw a0, pixel_x
    lw a1, pixel_y
    li a2, COLOR_BLANCO
    jal pintar_pixel
	
espera_teclado:
    # Consultar el registro de estado del teclado.
    li t0, KEY_STATUS_ADDRESS
    lw t1, 0(t0)
    beqz t1, espera_teclado

    jal mover_pixel

    # Limpiar el estado del teclado.
    li t0, KEY_STATUS_ADDRESS
    sw zero, 0(t0)
    j espera_teclado

# Función: mover_pixel
# Parametros:
#	Ninguna
# Retorno:
#	Void
mover_pixel:
	addi sp, sp -4
	sw ra, 0(sp)

	lw a0, pixel_x 
	lw a1, pixel_y	
	li a2, COLOR_AZUL
	
	lw t0, KEY_INPUT_ADDRESS
	
	.mover_arriba:
		li t1, ASCII_W
		bne t0, t1, .mover_abajo
		addi a1, a1, -1 #Mover arriba
		jal verificar_colision
		bnez a0, .end_mover_pixel
		lw s0, pixel_x 
		lw s1, pixel_y	
		addi s1, s1, -1
		j .mover_pixel_final
	
	.mover_abajo:
		li t1, ASCII_S
		bne t0, t1, .mover_izquierda
		addi a1, a1, 1 #Mover abajo
		jal verificar_colision
		bnez a0, .end_mover_pixel
		lw s0, pixel_x 
		lw s1, pixel_y	
		addi s1, s1, 1
		j .mover_pixel_final
		
	.mover_izquierda:
		li t1, ASCII_A
		bne t0, t1, .mover_derecha
		addi a0, a0, -1 #Mover izquierda
		jal verificar_colision
		bnez a0, .end_mover_pixel
		lw s0, pixel_x 
		lw s1, pixel_y	
		addi s0, s0, -1
		j .mover_pixel_final
		
	.mover_derecha:
		li t1, ASCII_D
		bne t0, t1, .mover_pixel_final
		addi a0, a0, 1 #Mover derecha
		jal verificar_colision
		bnez a0, .end_mover_pixel
		lw s0, pixel_x 
		lw s1, pixel_y	
		addi s0, s0, 1
		j .mover_pixel_final
	
	.mover_pixel_final:
	
	lw a0, pixel_x 
	lw a1, pixel_y
	li a2, COLOR_NEGRO
	jal pintar_pixel
	
	mv a0, s0
	mv a1, s1
	li a2, COLOR_BLANCO
	jal pintar_pixel
	
	sw s0, pixel_x, t1
	sw s1, pixel_y, t1
	.end_mover_pixel: 
	lw ra, 0(sp)
	addi sp, sp, 4
	jr ra

# Function: Pintar_Pixel
# Parámetros:
#	a0: Coordenada x
#	a1: Coordenada y
#	a2: Color
# Return
#	void
pintar_pixel:
	addi sp, sp -8
	sw ra, 0(sp)
	sw s0, 4(sp)
	
	mv s0, a2
	jal calcular_posicion_fb	
	sw s0, (a0)
	
	lw s0, 4(sp)
	lw ra, 0(sp)
	addi sp, sp, 8
	jr ra

# Funcion: pintar_bloque
# Parametros:
#	a0: x (esquina superior izquierda)
#	a1: y (esquina superior izquierda)
#	a2: color
#	a3: w
#	a4: h
# Return
#	void
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
	addi s3, a3, -1
	addi s4, a4, -1
	
	.bloque_loop:
		mv a0, s0
		mv a1, s1
		mv a2, s2
		mv a3, s3
		jal pintar_linea_horizontal
		addi s1, s1, 1
		addi s4, s4, -1
		
		bgez s4, .bloque_loop
	
	lw s4, 20(sp)
	lw s3, 16(sp)
	lw s2, 12(sp)
	lw s1, 8(sp)
	lw s0, 4(sp)
	lw ra, 0(sp)
	addi sp, sp, 24	
	
	jr ra	
	
# Function: pintar_linea_horizontal
# Parametros:
#	a0: x
#	a1: y
#	a2: color
#	a3: w
# Return
#	void
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
	
	.h_loop:
		add a0, s0, s3
		mv a1, s1
		mv a2, s2
		jal pintar_pixel
		addi s3, s3, -1
		
		bgez s3, .h_loop
	
	lw s3, 16(sp)
	lw s2, 12(sp)
	lw s1, 8(sp)
	lw s0, 4(sp)
	lw ra, 0(sp)
	addi sp, sp, 20	
	
	jr ra

# Function: pintar_linea_vertical
# Parameters:
#	a0: x
#	a1: y
#	a2: color
#	a3: h
# Return
#	void
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
	
	.v_loop:
		mv a0, s0
		add a1, s1, s3
		mv a2, s2
		jal pintar_pixel
		addi s3, s3, -1
		
		bgez s3,.v_loop
	
	lw s3, 16(sp)
	lw s2, 12(sp)
	lw s1, 8(sp)
	lw s0, 4(sp)
	lw ra, 0(sp)
	addi sp, sp, 20	
	
	jr ra

# Function: pintar_letra_e
# Parameters:
#	a0: x
#	a1: y
#	a2: color
#	a3: h
# Return
#	void
pintar_letra_e:			
	addi sp, sp -20
	sw ra, 0(sp)
	sw s0, 4(sp)
	sw s1, 8(sp)
	sw s2, 12(sp)
	sw s3, 16(sp)
	
	mv s0, a0
	mv s1, a1
	mv s2, a2
	mv s3, a3

	jal pintar_linea_vertical
	
	mv a0, s0
	addi a0, a0, 1
	mv a1, s1
	mv a2, s2
	jal pintar_pixel
	
	mv a0, s0
	addi a0, a0, 1
	mv a1, s1
	addi a1, a1, 2
	mv a2, s2
	jal pintar_pixel
	
	mv a0, s0
	addi a0, a0, 1
	mv a1, s1
	addi a1, a1, 4
	mv a2, s2
	jal pintar_pixel
	
	lw ra, 0(sp)
	lw s0, 4(sp)
	lw s1, 8(sp)
	lw s2, 12(sp)
	lw s3, 16(sp)
	addi sp, sp, 20
	jr ra
		
# Function: pintar_letra_a
# Parameters:
#	a0: x
#	a1: y
#	a2: color
#	a3: h
# Return
#	void
pintar_letra_a:			
	addi sp, sp -20
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
	li a3, 2
	jal pintar_linea_horizontal
			
	lw ra, 0(sp)
	lw s0, 4(sp)
	lw s1, 8(sp)
	lw s2, 12(sp)
	lw s3, 16(sp)
	addi sp, sp, 20
	jr ra

# Function: calcular_posicion_fb
# Parametros:
#	a0: x
#	a1: y
# Return
#	a0: dirección en el framebuffer
calcular_posicion_fb:	
	li t0, 6 # Por el tamaño de la pantalla
	sll t0, a1, t0 # Se debe multiplicar y por 64 
	add t1, a0, t0 # Correspondiente  al largo de la pantalla
	li t0, 2
	sll t1, t1, t0 # Se multiplica la coordenada restante por 4
	add a0, t1, gp # Debido a que la memoria se avanza en bytes
	jr ra

# Function: verificar_colision
# Parameters:
#	a0: x
#	a1: y
#	a2: color
# Return
#	a0: 0 no colision, 1 colision
verificar_colision:
addi sp, sp -4
	sw ra, 0(sp)
	
	jal calcular_posicion_fb
	lw t3, (a0)
	
	beq t3, a2, .hay_colision
	.no_hay_colision
		li a0, 0
		j .end_colision
	.hay_colision:
		li a0, 1
	.end_colision:
		lw ra, 0(sp)
	
	addi sp, sp, 4
	jr ra
	
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
    addi sp, sp, -16
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
    addi sp, sp, 16
    ret

