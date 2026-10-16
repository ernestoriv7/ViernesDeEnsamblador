# 🧠🔥 Viernes de Ensamblador

Repositorio oficial de la serie **"Viernes de Ensamblador"** del canal  
📺 **Era Ingeniería**

---

## 🎯 ¿De qué trata esta serie?

Esta serie nace para responder una pregunta simple pero poderosa:

> **¿Qué hace realmente la computadora cuando ejecuta un programa?**

Aquí aprenderás **Ensamblador RISC-V** sin magia, sin humo y sin abstracciones innecesarias.
Cada viernes desarmamos el software capa por capa hasta que quede claro **qué ocurre dentro del procesador**.

---

## 🚀 Contenido del repositorio

En este repositorio encontrarás:

- ✅ Código fuente usado en los episodios
- ✅ Ejemplos didácticos en Ensamblador RISC-V
- ✅ Pruebas y experimentos reales
- ✅ Evolución progresiva del código


Cada carpeta corresponde a un episodio específico de la serie.

---

## 🛠️ Requisitos

Dependiendo del episodio se utilizará:

- 🧵 **Simulador RARS**
- 🧠 Muchas ganas de entender cómo funcionan las cosas de verdad

Los requisitos exactos se especifican en cada carpeta.

---

## ▶️ Cómo usar este repositorio

1️⃣ Clona el repositorio:

```bash
git clone https://github.com/TU-USUARIO/viernes-de-ensamblador.git
cd viernes-de-ensamblador
```

2️⃣ Ingresa al episodio que te interese
3️⃣ Compila y ejecuta los ejemplos
4️⃣ Mira el video correspondiente para entender **qué está pasando internamente**

---

## 📺 Playlist de YouTube

Todos los episodios están disponibles en:

👉 **Serie Viernes de Ensamblador – Era Ingeniería**  
[*(enlace a la playlist aquí)*](https://www.youtube.com/watch?v=NaqfodLr7dw&list=PLE7u-WR1XaFOAtZKFB267eOzdaHNwW-X1)

> 💡 Recomendación: mira el video y luego experimenta con el código.

---

## Battle City: Ejemplo 17

Abre [Ejemplo_17.asm](Ejemplo_17/Ejemplo_17.asm) en RARS y conecta las
herramientas **Bitmap Display** y **Keyboard and Display MMIO Simulator**
antes de ejecutar. Introduce las teclas en el teclado de la herramienta MMIO.

- **W, A, S, D**: mover y orientar el tanque.
- **Espacio**: disparar un proyectil blanco de un píxel en la dirección del cañón.
- Solo puede haber un proyectil activo; avanza automáticamente cada 40 ms.
- Cada impacto en ladrillo abre una franja de hasta 5 píxeles de ancho y
  2 de profundidad. Los huecos permanecen y permiten el paso del tanque.
- El acero detiene el disparo sin romperse; el agua permite que pase el disparo,
  pero no el tanque. Este ejemplo no implementa mejoras de armamento.
- Destruir la base (incluido su emblema blanco) termina la partida, la pinta
  de rojo y muestra un mensaje. Reinicia el programa en RARS para volver a jugar.

### Cómo explicar el programa

[Ejemplo_17.asm](Ejemplo_17/Ejemplo_17.asm) está dividido en diez secciones
numeradas. Conviene empezar por el estado y el bucle, y después seguir las
llamadas hacia las rutinas de menor nivel:

1. **Configuración:** teclas, colores, geometría y servicios de RARS tienen
   constantes con nombre, en lugar de números sin contexto.
2. **Estado:** `tank_*` guarda el tanque; `proyectil_*` guarda el disparo.
   `partida_terminada` indica si la base fue destruida.
3. **Bucle:** inicializa la escena una vez; después actualiza el proyectil,
   procesa una tecla y hace una pausa corta. Tras la derrota, conserva la
   escena sin aceptar más acciones.
4. **Nivel:** una tabla describe los rectángulos del escenario como
   `(x, y, color, ancho, alto)`.
5. **Movimiento:** propone una posición, comprueba la huella completa de
   5×5 y confirma el movimiento solo si está libre. El giro sí se conserva
   cuando hay un obstáculo.
6. **Terreno:** `mapa_terreno` es el modelo persistente; el framebuffer es
   la imagen visible. Restaurar un sprite copia su fondo del modelo, en vez
   de borrar indiscriminadamente con negro.
7. **Disparo:** crea, temporiza, mueve y resuelve el proyectil. El impacto
   modifica el terreno si encuentra ladrillo, o termina la partida si
   encuentra la base.
8. **Dibujo:** compone los sprites con píxeles, líneas y rectángulos;
   estas rutinas no cambian el terreno.
9. **Utilidades originales:** conserva las rutinas de letras, separadas de
   la lógica del juego.
10. **Memoria y colisiones:** convierte coordenadas en direcciones y
    comprueba los límites y materiales de cada píxel del destino.

El flujo principal puede explicarse sin comenzar por instrucciones individuales:

```text
inicializar escena
repetir:
    si la partida sigue activa:
        actualizar proyectil
        si el impacto no terminó la partida:
            procesar entrada
    pausar brevemente
```

Cada píxel ocupa cuatro bytes: su dirección es
`base + (y * 64 + x) * 4`. La base es `gp` para la pantalla, o la dirección
de `mapa_terreno` para el modelo. `(0, 0)` está arriba a la izquierda.

Las cabeceras de las rutinas describen sus entradas, resultados y efectos.
Se sigue la convención RISC-V: `a*` para argumentos y resultados, `t*` para
temporales, `s*` para valores que deben sobrevivir a llamadas y `ra` para
el retorno. Las rutinas que llaman a otras guardan `ra` y los registros
`s*` que utilizan. En este ejemplo autónomo de RARS se reservan exactamente
**4 bytes por registro guardado**, sin espacio de relleno: un registro
requiere 4 bytes; dos, 8; cinco, 20. La reserva y la liberación siempre
usan la misma cantidad. Esto se aparta deliberadamente de la alineación
de 16 bytes de la ABI estándar; no es una convención para interoperar con
código compilado o bibliotecas externas.

Para comprobar el ensamblado desde la raíz, sin abrir herramientas gráficas:

```powershell
java -jar .\rars1_6.jar nc a ae1 .\Ejemplo_17\Ejemplo_17.asm
```

---

## Battle City: Ejemplo 18 — el primer enemigo

[Ejemplo_18.asm](Ejemplo_18/Ejemplo_18.asm) retoma el nivel 1 del ejemplo
anterior, añade el **primer tanque enemigo** y reorganiza todo el programa
en tres capas para poder explicarlo por partes en videos cortos.

Configura el **Bitmap Display** (unidades de 8×8, pantalla de 64×64, base
`gp`) y el **Keyboard and Display MMIO Simulator** antes de ejecutar.

- **W, A, S, D**: mantener para mover y orientar el tanque azul.
  **Espacio**: disparar. Cada evento del auto-repeat avanza dos píxeles; al
  soltar la tecla dejan de llegar eventos y el tanque se detiene.
- El enemigo (blanco con cañón rojo) aparece en la esquina superior
  izquierda, patrulla el nivel con rumbo aleatorio y dispara solo.
- Cada bando tiene un único proyectil en vuelo; avanza 2 píxeles por cuadro.
- Un impacto en ladrillo abre un boquete de 5×2 perpendicular al disparo;
  el acero detiene la bala y el agua la deja pasar.
- Una bala enemiga hace reaparecer al jugador en su posición inicial. Cuando
  una bala alcanza al enemigo, este desaparece. Solo perder la base termina
  la partida.

### Las tres capas

1. **Modelo.** `mapa_terreno` guarda un color por píxel del escenario;
   `tanque_jugador` y `tanque_enemigo` son dos registros con el mismo formato
   de campos (`T_X`, `T_Y`, `T_DIR`, `T_VIVO`, colores y temporizadores), y
   `bala_jugador` / `bala_enemigo` usan el formato `B_*`.
2. **Lógica.** `procesar_entrada`, `actualizar_enemigo` y `actualizar_balas`
   solo leen y modifican el modelo; nunca tocan la pantalla.
3. **Vista.** `dibujar_escena` reconstruye el cuadro completo en
   `buffer_frame`: copia el terreno y encima dibuja tanques y balas. Solo
   después presenta el resultado en `gp`, por lo que nunca se muestra un
   cuadro intermedio sin sprites.

```text
construir escenario
repetir cada cuadro (16 ms):
    procesar entrada del jugador
    actualizar enemigo (reloj de movimiento y reloj de disparo)
    avanzar las balas píxel a píxel
    dibujar la escena
hasta que la partida termine
```

### Detalles útiles para explicarlo

- **Tablas en vez de cadenas de `if`.** `direccion_dx` / `direccion_dy`
  convierten una dirección en un desplazamiento, y `canon_sprite` /
  `orugas_sprite` describen el sprite de 5×5 sin una sola comparación.
- **Un mismo dibujante, tres lienzos.** `escribir_pixel` y `rellenar_rect`
  reciben la dirección base del lienzo: `mapa_terreno` para el modelo,
  `buffer_frame` para componer el cuadro y `gp` para la pantalla visible.
  La dirección de un píxel siempre es `base + (y * 64 + x) * 4`.
- **Funciones con punteros.** `mover_tanque`, `disparar` y `actualizar_bala`
  reciben un puntero al registro de la entidad, así que el mismo código vale
  para el jugador y para el enemigo.
- **IA del enemigo.** Dos contadores decrecientes: uno marca cuándo avanzar
  y otro cuándo disparar. Si queda bloqueado —o con una probabilidad
  pequeña— elige una dirección nueva con el servicio 42 de RARS.
- **Pantalla rápida y sin parpadeo.** El escenario se copia completo a
  `buffer_frame` solo al iniciar. Después se restauran y presentan únicamente
  los pequeños rectángulos ocupados por los sprites anteriores y actuales.

Para comprobar el ensamblado desde la raíz, sin abrir herramientas gráficas:

```powershell
java -jar .\rars1_6.jar nc a ae1 .\Ejemplo_18\Ejemplo_18.asm
```

---


## 🧩 ¿A quién va dirigido?

- Estudiantes de ingeniería
- Programadores curiosos
- Personas que quieren entender qué ocurre realmente al ejecutar código
- Desarrolladores de sistemas, videojuegos o seguridad
- Gente cansada de programar como caja negra

---

## 🧠 Filosofía

> *Si no entiendes el ensamblador, no entiendes realmente lo que ejecuta tu programa.*

Aquí el ensamblador no es un fin, es una **herramienta para razonar mejor sobre software**.

---


## 📜 Licencia

Este proyecto se publica bajo licencia **MIT**.
Puedes usarlo, modificarlo y compartirlo libremente.

---

## 👨‍💻 Autor

**Ernesto Rivera Alvarado**  
📺 YouTube: *Era Ingeniería*  
🎮 Videojuegos educativos · 🧠 Sistemas · ⚙️ Assembly
