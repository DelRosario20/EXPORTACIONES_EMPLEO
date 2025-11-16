******************************************************
* 			ESTUDIO EMPLEO Y EXPORTACIONES			 *
******************************************************

* Configuraciones iniciales
clear all
set more off
macro drop _all 

* Definir directorio de trabajo
cd "C:\Users\USER\Documents\ESTUDIO_EMPLEO_EXPORTACIONES"

* Crear carpetas para outputs
capture mkdir "resultados"
capture mkdir "resultados/graficos" 
capture mkdir "resultados/tablas"

* Log file
log using "resultados/analisis_exportaciones_empleo.log", replace

/*==============================================================================
  1. CARGA Y PREPARACIÓN DE DATOS
==============================================================================*/

* Carga de la base de datos
import delimited "Data\Data_OFICIAL_DELIMITADO.csv", varnames(1) clear

* Verificar estructura de datos
describe
summarize

* Renombrar variables si es necesario (minúsculas)
rename *, lower

/*==============================================================================
  2. CONFIGURACIÓN DE SERIE DE TIEMPO
==============================================================================*/
* Convertir tiempo_q a formato trimestral numérico
gen tiempo = quarterly(trimestre, "YQ") 
format tiempo %tq 

* Establecer datos de series de tiempo
tsset tiempo

* Verificar que no hay gaps en la serie
tsreport

* Etiquetar la variable de tiempo
label variable tiempo "Período trimestral"

/*==============================================================================
  3. TRANSFORMACIONES LOGARÍTMICAS
==============================================================================*/
* Logaritmo de Exportaciones
gen log_exportaciones = ln(exportaciones)
label variable log_exportaciones "Log(EXPORTACIONES)"

* Logaritmo de Salario Real
gen log_salario_real = ln(salario_real)
label variable log_salario_real "Log(SALARIO_REAL)"

* Logaritmo de TCER
gen log_tcer = ln(tcer)
label variable log_tcer "Log(TCER)"

* Verificar si hay IED (puede tener valores negativos o cero)
quietly summarize balanza_comercial
scalar min_balanza = r(min)

* Para IED/Balanza Comercial: crear versión ajustada si hay valores negativos
gen balanza_ajustada = balanza_comercial - min_balanza + 1
gen log_balanza = ln(balanza_ajustada)
label variable log_balanza "Log(BALANZA_COMERCIAL ajustada)"

* Calcular participación de exportaciones no petroleras
gen part_no_petro = (exp_no_petroleras / exportaciones) * 100
label variable part_no_petro "Participación Export. No Petroleras (%)"

/*==============================================================================
  4. CREACIÓN DE VARIABLE DEPENDIENTE BINARIA
==============================================================================*/
* Generar cambio en Tasa de Empleo
gen delta_tasa_empleo = D.tasa_empleo
label variable delta_tasa_empleo "Cambio en Tasa de Empleo"

* Crear variable binaria: 1 si aumenta el empleo, 0 si no
gen crecimiento_empleo = (delta_tasa_empleo > 0 & delta_tasa_empleo != .)
replace crecimiento_empleo = . if delta_tasa_empleo == .
label variable crecimiento_empleo "Crecimiento del Empleo (1=Sí, 0=No)"

* Estadísticas descriptivas de la variable dependiente
tabulate crecimiento_empleo, missing
summarize delta_tasa_empleo, detail

/*==============================================================================
  CRITERIO 1: ANÁLISIS DE RAÍCES UNITARIAS EN NIVELES
==============================================================================*/
* Prueba ADF para LOG_EXPORTACIONES (niveles)
dfuller log_exportaciones, lags(4) regress

* Prueba ADF para LOG_SALARIO_REAL (niveles)
dfuller log_salario_real, lags(4) regress

* Prueba ADF para LOG_TCER (niveles)
dfuller log_tcer, lags(4) regress

* Prueba ADF para TASA_CREC_EXPORT (niveles)
dfuller tasa_crec_export, lags(4) regress

* Prueba ADF para PART_NO_PETRO (niveles)
dfuller part_no_petro, lags(4) regress

/*==============================================================================
  CRITERIO 2: PRUEBAS ADF EN PRIMERAS DIFERENCIAS
==============================================================================*/
* Generar primeras diferencias
gen d_log_exportaciones = D.log_exportaciones
gen d_log_salario_real = D.log_salario_real
gen d_log_tcer = D.log_tcer
gen d_tasa_crec_export = D.tasa_crec_export
gen d_part_no_petro = D.part_no_petro

* Prueba ADF en primeras diferencias
dfuller d_log_exportaciones, lags(4) regress

dfuller d_log_salario_real, lags(4) regress

dfuller d_log_tcer, lags(4) regress

dfuller d_tasa_crec_export, lags(4) regress

dfuller d_part_no_petro, lags(4) regress


/*==============================================================================
  CRITERIO 3: ESTIMACIÓN DEL MODELO LOGIT
==============================================================================*/
* Modelo Logit con rezagos (capturando dinámica de corto plazo)
logit crecimiento_empleo L.log_exportaciones L.tasa_crec_export L.part_no_petro ///
      L.log_salario_real L.log_tcer, nolog

* Guardar estimaciones
estimates store modelo_logit

* Reporte detallado
logit, or

/*==============================================================================
  CRITERIO 4: SIGNIFICANCIA DE LOS COEFICIENTES
==============================================================================*/

display _newline(2) "========================================" _newline ///
                   "CRITERIO 4: TESTS DE SIGNIFICANCIA" _newline ///
                   "========================================" _newline

* Test de Wald para significancia individual (ya reportado en la tabla del modelo)
display _newline ">>> Test de Wald Individual (ver tabla anterior)" _newline

* Test de Razón de Verosimilitud (LR) para significancia conjunta
* Primero estimamos modelo nulo (solo constante)
display _newline ">>> Estimando Modelo Nulo (solo constante)..." _newline
quietly logit crecimiento_empleo
estimates store modelo_nulo

* Restaurar modelo completo
estimates restore modelo_logit

* Test LR: comparar modelo completo vs modelo nulo
display _newline ">>> Test de Razón de Verosimilitud (LR)" _newline
lrtest modelo_logit modelo_nulo

* Interpretación automática
display _newline "Interpretación:" _newline ///
        "H0: Todos los coeficientes (excepto constante) = 0" _newline ///
        "Si p-value < 0.05 → Rechazamos H0 → El modelo completo es significativamente mejor"

* Pseudo R-squared y clasificación
display _newline ">>> Capacidad Clasificatoria del Modelo" _newline
estat classification

/*==============================================================================
  CRITERIO 5: DIAGNÓSTICO DEL MODELO
==============================================================================*/
* a) Test de Bondad de Ajuste (Hosmer-Lemeshow)
estat gof, group(10) table

* b) Evaluación de Multicolinealidad (VIF)
* Nota: para logit usamos regresión auxiliar
quietly reg L.log_exportaciones L.tasa_crec_export L.part_no_petro ///
           L.log_salario_real L.log_tcer
vif

* c) Capacidad Predictiva - Matriz de Confusión
estimates restore modelo_logit
estat classification

* d) Curva ROC y Área Bajo la Curva
lroc, nograph

/*==============================================================================
  CRITERIO 6: ANÁLISIS DE RESIDUOS
==============================================================================*/

display _newline(2) "========================================" _newline ///
                   "CRITERIO 6: ANÁLISIS DE RESIDUOS" _newline ///
                   "========================================" _newline

* Eliminar variables de predicción previas si existen
capture drop prob_empleo
capture drop residuos_respuesta
capture drop residuos_pearson
capture drop residuos_deviance

* Restaurar modelo
quietly estimates restore modelo_logit

* 1. Predecir probabilidades (esto SÍ funciona)
predict prob_empleo if e(sample), pr
label variable prob_empleo "Probabilidad predicha de crecimiento"

* 2. Calcular RESIDUOS DE RESPUESTA manualmente
* Residuos = Observado - Predicho
gen residuos_respuesta = crecimiento_empleo - prob_empleo if e(sample)
label variable residuos_respuesta "Residuos de respuesta"

* 3. Calcular RESIDUOS DE PEARSON manualmente
* Fórmula: (y - p) / sqrt(p * (1-p))
gen residuos_pearson = (crecimiento_empleo - prob_empleo) / ///
                        sqrt(prob_empleo * (1 - prob_empleo)) if e(sample)
label variable residuos_pearson "Residuos de Pearson"

* 4. Calcular RESIDUOS DEVIANCE manualmente
* Fórmula para Logit Binomial:
* d = sign(y - p) * sqrt(-2 * [y*ln(p) + (1-y)*ln(1-p)])
gen residuos_deviance = .
replace residuos_deviance = sqrt(-2 * log(prob_empleo)) ///
    if crecimiento_empleo == 1 & e(sample)
replace residuos_deviance = sqrt(-2 * log(1 - prob_empleo)) ///
    if crecimiento_empleo == 0 & e(sample)
replace residuos_deviance = -residuos_deviance ///
    if crecimiento_empleo < prob_empleo & e(sample)
label variable residuos_deviance "Residuos de deviance"

* Estadísticas descriptivas de residuos
display _newline ">>> Estadísticas Descriptivas de Residuos" _newline
summarize residuos_respuesta residuos_pearson residuos_deviance if e(sample)

* Prueba de Normalidad (Jarque-Bera) en residuos de Pearson
display _newline ">>> Test de Normalidad de Residuos de Pearson (Jarque-Bera)" _newline
summarize residuos_pearson if e(sample), detail
sktest residuos_pearson

* Prueba de Normalidad en residuos de respuesta
display _newline ">>> Test de Normalidad de Residuos de Respuesta" _newline
sktest residuos_respuesta

* Gráfico 1: Residuos de Pearson vs Tiempo
scatter residuos_pearson tiempo if e(sample), yline(0) ///
    title("Residuos de Pearson vs Tiempo") ///
    ytitle("Residuos de Pearson") xtitle("Período Trimestral") ///
    mcolor(navy) msize(medium)
graph export "resultados/graficos/residuos_pearson.pdf", replace

* Gráfico 2: Residuos de Respuesta vs Tiempo
scatter residuos_respuesta tiempo if e(sample), yline(0) ///
    title("Residuos de Respuesta vs Tiempo") ///
    ytitle("Residuos de Respuesta") xtitle("Período Trimestral") ///
    mcolor(maroon) msize(medium)
graph export "resultados/graficos/residuos_respuesta.pdf", replace

* Gráfico 3: Residuos Deviance vs Tiempo
scatter residuos_deviance tiempo if e(sample), yline(0) ///
    title("Residuos Deviance vs Tiempo") ///
    ytitle("Residuos Deviance") xtitle("Período Trimestral") ///
    mcolor(forest_green) msize(medium)
graph export "resultados/graficos/residuos_deviance.pdf", replace

* Gráfico 4: Histograma de Residuos de Pearson
histogram residuos_pearson if e(sample), normal ///
    title("Distribución de Residuos de Pearson") ///
    xtitle("Residuos de Pearson") ///
    fcolor(navy%30) lcolor(navy)
graph export "resultados/graficos/hist_residuos_pearson.pdf", replace

* Gráfico 5: Histograma de Residuos de Respuesta
histogram residuos_respuesta if e(sample), normal ///
    title("Distribución de Residuos de Respuesta") ///
    xtitle("Residuos de Respuesta") ///
    fcolor(maroon%30) lcolor(maroon)
graph export "resultados/graficos/hist_residuos_respuesta.pdf", replace

* Gráfico 6: Q-Q plot para normalidad
qnorm residuos_pearson if e(sample), ///
    title("Q-Q Plot: Residuos de Pearson") ///
    mcolor(navy)
graph export "resultados/graficos/qqplot_pearson.pdf", replace

* Prueba de Autocorrelación en residuos
display _newline ">>> Análisis de Autocorrelación en Residuos" _newline
* Correlación serial de primer orden
quietly correlate residuos_pearson L.residuos_pearson if e(sample)
display "Correlación de primer orden: " r(rho)

* Estadística de Durbin-Watson aproximada
* DW ≈ 2(1 - ρ)
scalar rho_1 = r(rho)
scalar dw_aprox = 2 * (1 - rho_1)
display "Estadística Durbin-Watson (aproximada): " dw_aprox
display "Interpretación: DW ≈ 2 indica ausencia de autocorrelación"

/*==============================================================================
  CRITERIO 7: RAÍZ UNITARIA EN RESIDUOS
==============================================================================*/
* Prueba ADF en residuos de Pearson
dfuller residuos_pearson if e(sample), lags(4) regress

* Interpretación: Si rechazo H0, los residuos son estacionarios I(0) ✓

/*==============================================================================
  8. EFECTOS MARGINALES Y ANÁLISIS ADICIONAL
==============================================================================*/
* Efectos marginales promedio
margins, dydx(*) atmeans

* Efectos marginales en la media de cada variable
margins, dydx(L.log_exportaciones L.tasa_crec_export L.part_no_petro ///
              L.log_salario_real L.log_tcer)

/*==============================================================================
  9. EXPORTACIÓN DE RESULTADOS
==============================================================================*/

* Tabla de resultados del modelo
estimates restore modelo_logit
esttab using "resultados/tablas/modelo_logit.tex", ///
    replace b(3) se(3) star(* 0.10 ** 0.05 *** 0.01) ///
    label title("Modelo Logit: Determinantes del Crecimiento del Empleo")

* Resumen de pruebas ADF
log close