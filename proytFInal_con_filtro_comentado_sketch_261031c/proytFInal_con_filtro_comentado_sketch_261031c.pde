import processing.serial.*;
import java.io.DataOutputStream;
import java.io.DataInputStream;
import java.io.EOFException;
import java.io.IOException;

Serial puerto;
int valorECG = 512; 

float xPos = 252;   
float lastX = 252;
float lastY = 250;

boolean modoVivo = true;
boolean congelado = false;

// Paleta de Colores (Tema del Monitor)
// Cámbialos aquí para transformar todo el diseño visual
color colorFondo = color(10, 15, 10);
color colorOnda = color(0, 255, 100);       // Verde brillante clásico
color colorOndaHistorial = color(0, 200, 255); // Celeste
color colorGrillaFina = color(20, 50, 20);
color colorGrillaGruesa = color(40, 90, 40);
color colorTextoPrincipal = color(0, 255, 100);
color colorTextoSecundario = color(150);
color colorBotonActivo = color(0, 150, 255);
color colorBotonInactivo = color(50);

// Variables Clínicas y Algoritmo de Detección
int ultimoTiempoPico = 0;
int intervaloRR = 0;
int rrAnterior = 0;
int bpm = 0;
int hrv = 0;
String nivelEstres = "Recopilando...";

// Variables para el Ritmo Respiratorio (EDR)
String ritmoRespiratorio = "Calculando...";
int rpmReal = 0;
int anteriorMaxLocal = 0;
int tendenciaResp = 0; 
int ultimoTiempoResp = 0;

int umbralPico = 650; 
int maxLocal = 0;
int tiempoMaxLocal = 0;
boolean enPico = false;

// Nodos y gestión de memoria dinámica
class NodoECG {
  int valor;
  int tiempo;
  NodoECG siguiente;
  NodoECG(int v, int t) { valor = v; tiempo = t; siguiente = null; }
}
NodoECG cabeza = null;
NodoECG cola = null;
int cantidadNodos = 0; 

// Buffer para la vista estática del historial
int[] historialValores = new int[1000];
int muestrasHistorial = 0;

int factorFiltro = 10;
int[] bufferFiltro = new int[factorFiltro];
int indiceFiltro = 0;
int valorECGFiltrado = 512;

void setup() {
  size(1100, 600);
  background(colorFondo);
  frameRate(100); 
  
  if (Serial.list().length > 0) {
    puerto = new Serial(this, Serial.list()[0], 9600);
    puerto.bufferUntil('\n');
  }
  dibujarCuadriculaMedica();
}

void draw() {
  // 1. PANEL IZQUIERDO (0 a 250)
  noStroke(); fill(20); rect(0, 0, 250, height);
  
  fill(colorTextoPrincipal); textAlign(LEFT, TOP);
  textSize(20); text("PARÁMETROS", 20, 20);
  
  textSize(50); text(modoVivo ? (bpm > 0 ? str(bpm) : "--") : "H", 20, 60);
  textSize(14); fill(colorTextoSecundario); text("BPM (Latidos por min)", 20, 115);
  
  fill(colorTextoPrincipal); textSize(35); text(modoVivo ? (hrv > 0 ? hrv + " ms" : "-- ms") : "--", 20, 150);
  fill(colorTextoSecundario); textSize(14); text("HRV (Variabilidad)", 20, 190);
  
  fill(colorTextoPrincipal); textSize(35); text(modoVivo ? (rpmReal > 0 ? ritmoRespiratorio : "-- rpm") : "--", 20, 225);
  fill(colorTextoSecundario); textSize(14); text("Ritmo Respiratorio", 20, 265);
  
  fill(color(255, 200, 0)); textSize(24); text(modoVivo ? nivelEstres : "Archivo", 20, 300);
  fill(colorTextoSecundario); textSize(14); text(modoVivo ? "Nivel de Estrés" : "Modo de Vista", 20, 335);

  dibujarBoton(20, 380, 210, 40, "Datos Actuales", modoVivo);
  dibujarBoton(20, 435, 210, 40, "Historial (Comprimido)", !modoVivo);
  dibujarBoton(20, 490, 210, 40, congelado ? "Descongelar Pantalla" : "Congelar Pantalla", congelado);
  dibujarBoton(20, 545, 210, 40, "Guardar Binario", false);

  // 2. OSCILOSCOPIO CENTRAL/DERECHO (250 a width)
  if (modoVivo) {
    if (!congelado) {
      float yPos = map(valorECGFiltrado, 0, 1023, height - 50, 50);
      
      noStroke(); fill(colorFondo); rect(xPos, 0, 40, height);
      
      for (int i = int(xPos); i < xPos + 40; i++) {
        if (i % 10 == 0 && i < width) {
          if (i % 50 == 0) { stroke(colorGrillaGruesa); strokeWeight(1.5); } 
          else { stroke(colorGrillaFina); strokeWeight(0.5); } 
          line(i, 0, i, height);
        }
      }
      for (int i = 0; i < height; i += 10) {
        if (xPos < width) {
          if (i % 50 == 0) { stroke(colorGrillaGruesa); strokeWeight(1.5); } 
          else { stroke(colorGrillaFina); strokeWeight(0.5); } 
          line(max(xPos, 250), i, min(xPos + 40, width), i);
        }
      }
      
      stroke(colorOnda); strokeWeight(2.5);
      line(lastX, lastY, xPos, yPos);
      
      lastX = xPos; lastY = yPos;
      xPos += 2;
      
      if (xPos >= width) {
        xPos = 252; lastX = 252;
        dibujarCuadriculaMedica();
      }
    }
  } else {
    dibujarCuadriculaMedica();
    if (muestrasHistorial > 0) {
      float pasoX = (float)(width - 250) / (muestrasHistorial - 1);
      stroke(colorOndaHistorial); 
      strokeWeight(2);
      
      for (int i = 0; i < muestrasHistorial - 1; i++) {
        float x1 = 250 + (i * pasoX);
        float y1 = map(historialValores[i], 0, 1023, height - 50, 50);
        float x2 = 250 + ((i + 1) * pasoX);
        float y2 = map(historialValores[i+1], 0, 1023, height - 50, 50);
        line(x1, y1, x2, y2);
      }
    }
  }
}

void serialEvent(Serial p) {
  String mensaje = trim(p.readStringUntil('\n'));
  if (mensaje != null && mensaje.length() > 0) {
    try {
      int datoCrudo = Integer.parseInt(mensaje);
      int tiempoActual = millis();
      
      // 1. Filtrado Digital
      bufferFiltro[indiceFiltro] = datoCrudo;
      indiceFiltro = (indiceFiltro + 1) % factorFiltro;
      int suma = 0;
      for (int i = 0; i < factorFiltro; i++) suma += bufferFiltro[i];
      valorECGFiltrado = suma / factorFiltro; 
      
      // 2. Detección de Pico R y Análisis Médico
      if (tiempoActual - ultimoTiempoPico > 250) { 
        
        if (valorECGFiltrado > umbralPico) {
          enPico = true;
          if (valorECGFiltrado > maxLocal) {
            maxLocal = valorECGFiltrado;
            tiempoMaxLocal = tiempoActual;
          }
        } 
        else if (enPico && valorECGFiltrado < umbralPico) {
          enPico = false;
          intervaloRR = tiempoMaxLocal - ultimoTiempoPico;
          ultimoTiempoPico = tiempoMaxLocal;
          
          if (rrAnterior > 0 && intervaloRR > 0) {
            bpm = 60000 / intervaloRR;
            hrv = abs(intervaloRR - rrAnterior);
            
            if (hrv < 15) nivelEstres = "Alto (Tenso)";
            else if (hrv < 40) nivelEstres = "Moderado";
            else nivelEstres = "Bajo (Relajado)";
          }
          rrAnterior = intervaloRR;
          
          // Algoritmo EDR (Frecuencia Respiratoria a partir del ECG)
          if (anteriorMaxLocal > 0) {
            if (maxLocal > anteriorMaxLocal) {
               tendenciaResp = 1; // La amplitud de los latidos está subiendo (Inhalación)
            } 
            else if (maxLocal < anteriorMaxLocal && tendenciaResp == 1) {
               // La amplitud bajó tras haber estado subiendo: ¡Encontramos el pico de una respiración!
               tendenciaResp = -1; 
               int intervaloResp = tiempoMaxLocal - ultimoTiempoResp;
               
               // Filtramos para aceptar solo ritmos biológicamente posibles (ej. entre 6 y 40 rpm)
               if (intervaloResp > 1500 && intervaloResp < 10000) { 
                  rpmReal = 60000 / intervaloResp;
                  ritmoRespiratorio = rpmReal + " rpm";
               }
               ultimoTiempoResp = tiempoMaxLocal;
            } 
            else if (maxLocal < anteriorMaxLocal) {
               tendenciaResp = -1; // Sigue bajando (Exhalación)
            }
          }
          anteriorMaxLocal = maxLocal; 
          maxLocal = 0; // Reinicio para el próximo latido
        }
      }
      
      // 3. Almacenamiento
      NodoECG nuevoNodo = new NodoECG(valorECGFiltrado, tiempoActual);
      if (cabeza == null) { 
        cabeza = nuevoNodo; cola = nuevoNodo; cantidadNodos++;
      } else { 
        cola.siguiente = nuevoNodo; cola = nuevoNodo; cantidadNodos++;
      }
      if (cantidadNodos > 1000) {
        cabeza = cabeza.siguiente;
        cantidadNodos--;
      }
    } catch (NumberFormatException e) {}
  }
}

void dibujarCuadriculaMedica() {
  noStroke(); fill(colorFondo); rect(250, 0, width - 250, height);
  for (int i = 250; i < width; i += 10) {
    if (i % 50 == 0) { stroke(colorGrillaGruesa); strokeWeight(1.5); } 
    else { stroke(colorGrillaFina); strokeWeight(0.5); }
    line(i, 0, i, height);
  }
  for (int i = 0; i < height; i += 10) {
    if (i % 50 == 0) { stroke(colorGrillaGruesa); strokeWeight(1.5); } 
    else { stroke(colorGrillaFina); strokeWeight(0.5); }
    line(250, i, width, i);
  }
}

void dibujarBoton(int x, int y, int w, int h, String texto, boolean activo) {
  if (activo) fill(colorBotonActivo); else fill(colorBotonInactivo); 
  rect(x, y, w, h, 5); 
  fill(255); textSize(14); textAlign(CENTER, CENTER); text(texto, x + w/2, y + h/2);
}

void mousePressed() {
  if (mouseX > 20 && mouseX < 230) {
    if (mouseY > 380 && mouseY < 420) {
      modoVivo = true; congelado = false; 
      dibujarCuadriculaMedica(); xPos = 252; lastX = 252; 
    }
    if (mouseY > 435 && mouseY < 475) { 
      modoVivo = false; congelado = true; cargarHistorialBinario(); 
    }
    if (mouseY > 490 && mouseY < 530) congelado = !congelado;
    if (mouseY > 545 && mouseY < 585) guardarHistorialBinario();
  }
}

void guardarHistorialBinario() {
  if (cabeza == null) return;
  try {
    DataOutputStream archivo = new DataOutputStream(createOutput("registro_ecg.dat"));
    NodoECG actual = cabeza; 
    while (actual != null) {
      archivo.writeInt(actual.tiempo); archivo.writeInt(actual.valor);  
      actual = actual.siguiente; 
    }
    archivo.flush(); archivo.close();
    println("Registro binario de 10 segundos guardado exitosamente.");
  } catch (IOException e) { println("Error al guardar archivo."); }
}

void cargarHistorialBinario() {
  muestrasHistorial = 0;
  try {
    DataInputStream archivo = new DataInputStream(createInput("registro_ecg.dat"));
    while (muestrasHistorial < 1000) {
      try {
        archivo.readInt();
        historialValores[muestrasHistorial] = archivo.readInt();
        muestrasHistorial++;
      } catch (EOFException e) { break; }
    }
    archivo.close();
  } catch (IOException e) { muestrasHistorial = 0; }
}
