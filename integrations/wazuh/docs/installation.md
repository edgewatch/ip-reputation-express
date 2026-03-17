# Instalación manual — Edgewatch Offline Wazuh Integration

Guía paso a paso para desplegar la integración en el servidor Wazuh manager.
Todos los comandos se ejecutan como **root** en el Wazuh manager.

---

## Requisitos previos

- Wazuh Manager 4.x instalado y operativo
- Acceso root al servidor Wazuh manager
- Conexión a internet para la primera descarga del dump (solo una vez)
- `curl` y `sha256sum` instalados (suelen estar disponibles por defecto)

---

## 1. Instalar el binario `ip-express`

Descarga el binario correspondiente a tu arquitectura desde
https://github.com/edgewatch/ip-reputation-express/tree/main/cli

```bash
# Linux amd64 (más común)
sudo install -m 755 ip-express-linux-amd64 /usr/local/bin/ip-express

# Linux arm64
sudo install -m 755 ip-express-linux-arm64 /usr/local/bin/ip-express

# Verifica que funciona
/usr/local/bin/ip-express --version
```

---

## 2. Crear directorio de trabajo de Edgewatch

```bash
sudo mkdir -p /var/ossec/integrations/edgewatch
sudo chown root:wazuh /var/ossec/integrations/edgewatch
sudo chmod 750 /var/ossec/integrations/edgewatch
```

---

## 3. Copiar los scripts de integración

```bash
# Script principal de integración
sudo cp integrations/custom-edgewatch-ip-reputation-express.py /var/ossec/integrations/
sudo chown root:wazuh /var/ossec/integrations/custom-edgewatch-ip-reputation-express.py
sudo chmod 750 /var/ossec/integrations/custom-edgewatch-ip-reputation-express.py

# Script de refresco del dump
sudo cp scripts/edgewatch-refresh-dump.sh /var/ossec/integrations/
sudo chown root:wazuh /var/ossec/integrations/edgewatch-refresh-dump.sh
sudo chmod 750 /var/ossec/integrations/edgewatch-refresh-dump.sh
```

Verifica los permisos:

```bash
ls -la /var/ossec/integrations/ | grep edgewatch
# Esperado:
# -rwxr-x--- root wazuh  custom-edgewatch-ip-reputation-express.py
# -rwxr-x--- root wazuh  edgewatch-refresh-dump.sh
# drwxr-x--- root wazuh  edgewatch/
```

---

## 4. Descargar el dump inicial

```bash
TARGET_DIR=/var/ossec/integrations/edgewatch \
IP_EXPRESS_BIN=/usr/local/bin/ip-express \
  /var/ossec/integrations/edgewatch-refresh-dump.sh
```

Salida esperada:
```
2026-03-11T14:00:00Z downloading dump from https://raw.githubusercontent.com/...
2026-03-11T14:00:05Z validating dump integrity
2026-03-11T14:00:05Z dump refresh successful: target=... sha256=abc123...
```

Verifica que el dump es válido:

```bash
/usr/local/bin/ip-express \
  --dump /var/ossec/integrations/edgewatch/latest.bin \
  --json info
```

---

## 5. Instalar las reglas de Wazuh

```bash
sudo cp rules/edgewatch-ip-reputation-express.xml /var/ossec/etc/rules/
sudo chown root:wazuh /var/ossec/etc/rules/edgewatch-ip-reputation-express.xml
sudo chmod 640 /var/ossec/etc/rules/edgewatch-ip-reputation-express.xml
```

---

## 6. Configurar `ossec.conf`

Edita `/var/ossec/etc/ossec.conf` y añade el bloque de integración **dentro** de `<ossec_config>`:

```bash
sudo nano /var/ossec/etc/ossec.conf
```

Añade (ajusta los `<group>` a los grupos que tengas en tu entorno):

```xml
<integration>
  <name>custom-edgewatch-ip-reputation-express.py</name>
  <group>authentication_failed,authentication_success,fortigate,web,windows</group>
  <alert_format>json</alert_format>
</integration>
```

> **Grupos disponibles en tu entorno**: compruébalos en el dashboard de Wazuh en
> `Threat Hunting → Events → Filtro por rule.groups`. Añade solo los que tengas.

---

## 7. Configurar la variable de entorno del dump

Para que el script use el dump gestionado en lugar del directorio home del usuario,
añade la variable de entorno. El método recomendado es via el fichero de entorno del sistema:

```bash
echo 'IPEXPRESS_DUMP_PATH=/var/ossec/integrations/edgewatch/latest.bin' \
  | sudo tee -a /etc/environment
```

O si prefieres configurarlo solo para el proceso Wazuh, añádelo al servicio systemd:

```bash
sudo systemctl edit wazuh-manager
```

```ini
[Service]
Environment="IPEXPRESS_DUMP_PATH=/var/ossec/integrations/edgewatch/latest.bin"
```

---

## 8. Programar el refresco del dump

El dump se debe actualizar periódicamente. Elige una opción:

### Opción A — cron (recomendado para simplicidad)

```bash
cat << 'EOF' | sudo tee /etc/cron.d/edgewatch-dump-refresh
# Refresca el dump de Edgewatch cada 30 minutos
*/30 * * * * root TARGET_DIR=/var/ossec/integrations/edgewatch IP_EXPRESS_BIN=/usr/local/bin/ip-express /var/ossec/integrations/edgewatch-refresh-dump.sh >> /var/ossec/logs/edgewatch-refresh.log 2>&1
EOF
sudo chmod 644 /etc/cron.d/edgewatch-dump-refresh
```

### Opción B — systemd timer (recomendado para entornos con systemd)

```bash
# Crear el servicio
cat << 'EOF' | sudo tee /etc/systemd/system/edgewatch-dump-refresh.service
[Unit]
Description=Refresh Edgewatch offline reputation dump

[Service]
Type=oneshot
ExecStart=/var/ossec/integrations/edgewatch-refresh-dump.sh
Environment="TARGET_DIR=/var/ossec/integrations/edgewatch"
Environment="IP_EXPRESS_BIN=/usr/local/bin/ip-express"
StandardOutput=append:/var/ossec/logs/edgewatch-refresh.log
StandardError=append:/var/ossec/logs/edgewatch-refresh.log
EOF

# Crear el timer
cat << 'EOF' | sudo tee /etc/systemd/system/edgewatch-dump-refresh.timer
[Unit]
Description=Run Edgewatch dump refresh every 30 minutes

[Timer]
OnBootSec=5min
OnUnitActiveSec=30min
Unit=edgewatch-dump-refresh.service

[Install]
WantedBy=timers.target
EOF

# Activar
sudo systemctl daemon-reload
sudo systemctl enable --now edgewatch-dump-refresh.timer

# Verifica que está activo
sudo systemctl status edgewatch-dump-refresh.timer
```

---

## 9. Reiniciar el Wazuh Manager

```bash
sudo systemctl restart wazuh-manager

# Verifica que arrancó sin errores
sudo systemctl status wazuh-manager
```

---

## 10. Validación

### 10.1 Verificar que las reglas se cargaron

```bash
sudo /var/ossec/bin/ossec-logtest 2>&1 | grep -i edgewatch
# Alternativa en Wazuh 4.x:
sudo /var/ossec/bin/wazuh-logtest
```

### 10.2 Test del binario con una IP conocida

```bash
# IP BLACKLISTED (resultado esperado: Verdict=BLACKLISTED, Score=1.0)
/usr/local/bin/ip-express \
  --dump /var/ossec/integrations/edgewatch/latest.bin \
  --json check 185.220.101.45

# IP limpia (resultado esperado: Verdict=CLEAN, Score bajo)
/usr/local/bin/ip-express \
  --dump /var/ossec/integrations/edgewatch/latest.bin \
  --json check 8.8.8.8
```

### 10.3 Test de integración completa

Inyecta un log SSH falso para disparar la integración:

```bash
# En el agente Wazuh (o en el manager si monitoriza /var/log/auth.log)
echo "$(date '+%b %d %H:%M:%S') $(hostname) sshd[9999]: Failed password for root from 185.220.101.45 port 22 ssh2" \
  | sudo tee -a /var/log/auth.log
```

Comprueba que la integración se ejecutó:

```bash
sudo tail -20 /var/ossec/logs/integrations.log | grep edgewatch
```

Busca en el dashboard de Wazuh un evento con:
```
integration: edgewatch_offline
edgewatch_offline.verdict: BLACKLISTED
```

### 10.4 Lista de verificación completa

- [ ] `/usr/local/bin/ip-express --version` devuelve versión
- [ ] `/var/ossec/integrations/edgewatch/latest.bin` existe y no está vacío
- [ ] `ip-express --dump .../latest.bin info` muestra metadatos del dump
- [ ] `ip-express --dump .../latest.bin check 185.220.101.45` devuelve `BLACKLISTED`
- [ ] `/var/ossec/integrations/custom-edgewatch-ip-reputation-express.py` tiene permisos `750 root:wazuh`
- [ ] `/var/ossec/etc/rules/edgewatch-ip-reputation-express.xml` existe
- [ ] `ossec.conf` contiene el bloque `<integration>custom-edgewatch-ip-reputation-express.py`
- [ ] `wazuh-manager` reiniciado y activo
- [ ] Cron o systemd timer configurado y activo
- [ ] Log de integración generado tras inyectar log de prueba
- [ ] Alerta visible en dashboard con `integration: edgewatch_offline`

---

## 11. Solución de problemas

### El script no se ejecuta (no hay logs en integrations.log)

```bash
# Verifica que el grupo está en ossec.conf
grep -A5 'custom-edgewatch-offline' /var/ossec/etc/ossec.conf

# Verifica que las reglas se cargaron
sudo /var/ossec/bin/wazuh-logtest
```

### Error "binary not found"

```bash
ls -la /usr/local/bin/ip-express
# Si no existe, repite el paso 1
```

### Error "dump file not found" o `lookup_error: true` en alertas

```bash
ls -lh /var/ossec/integrations/edgewatch/latest.bin
# Si no existe, repite el paso 4
```

### La integración se ejecuta pero no aparecen alertas enriquecidas

```bash
# Comprueba los logs de integración
sudo tail -50 /var/ossec/logs/integrations.log

# Verifica que la IP del log es pública (no 10.x, 192.168.x, 172.16-31.x)
# IPs privadas se marcan como skipped=True sin hacer lookup
```

### El dump no se refresca automáticamente

```bash
# Cron
sudo crontab -l | grep edgewatch
sudo cat /etc/cron.d/edgewatch-dump-refresh

# Systemd timer
sudo systemctl status edgewatch-dump-refresh.timer
sudo journalctl -u edgewatch-dump-refresh.service --since "1 hour ago"
```

---

## 12. Rollback

### Desactivar la integración rápidamente

```bash
# Elimina o comenta el bloque <integration> en ossec.conf y reinicia
sudo nano /var/ossec/etc/ossec.conf
sudo systemctl restart wazuh-manager
```

### Rollback del dump a la versión anterior

```bash
sudo cp /var/ossec/integrations/edgewatch/latest.bin.prev \
        /var/ossec/integrations/edgewatch/latest.bin
```

---

## 13. Despliegue en clúster Wazuh

En un clúster con varios managers (1 master + N workers), las reglas y la integración
deben gestionarse de forma diferente según el componente.

### Qué se sincroniza automáticamente

| Componente | ¿Sync automático? | Nodo destino |
|-----------|------------------|--------------|
| `rules/edgewatch-ip-reputation-express.xml` | **Sí** (Wazuh cluster) | Solo en master |
| `integrations/custom-edgewatch-ip-reputation-express.py` | **No** | Todos los managers |
| `scripts/edgewatch-refresh-dump.sh` | **No** | Todos los managers |
| `/usr/local/bin/ip-express` | **No** | Todos los managers |
| `ossec.conf` — bloque `<integration>` | **No** | Todos los managers |
| `/var/ossec/integrations/edgewatch/latest.bin` | **No** | Todos los managers |

### Procedimiento de instalación en clúster

#### Paso A — Reglas (solo en master)

```bash
# Ejecutar solo en el nodo MASTER
sudo cp rules/edgewatch-ip-reputation-express.xml /var/ossec/etc/rules/
sudo chown root:wazuh /var/ossec/etc/rules/edgewatch-ip-reputation-express.xml
sudo chmod 640 /var/ossec/etc/rules/edgewatch-ip-reputation-express.xml
# El master sincroniza las reglas a los workers automáticamente
```

#### Paso B — Integración (en TODOS los managers: master + workers)

Repite los pasos 1–9 de esta guía en cada nodo manager del clúster:

```bash
# En cada manager (master y workers):
sudo install -m 755 ip-express-linux-amd64 /usr/local/bin/ip-express
sudo mkdir -p /var/ossec/integrations/edgewatch
sudo chown root:wazuh /var/ossec/integrations/edgewatch
sudo chmod 750 /var/ossec/integrations/edgewatch
sudo cp integrations/custom-edgewatch-ip-reputation-express.py /var/ossec/integrations/
sudo chown root:wazuh /var/ossec/integrations/custom-edgewatch-ip-reputation-express.py
sudo chmod 750 /var/ossec/integrations/custom-edgewatch-ip-reputation-express.py
sudo cp scripts/edgewatch-refresh-dump.sh /var/ossec/integrations/
sudo chown root:wazuh /var/ossec/integrations/edgewatch-refresh-dump.sh
sudo chmod 750 /var/ossec/integrations/edgewatch-refresh-dump.sh
```

Añade el bloque `<integration>` al `ossec.conf` de **cada manager** (paso 6).

#### Paso C — Refresco del dump independiente por nodo (Opción A — cron)

Cada manager descarga y valida su propio dump de forma independiente.
Es la opción más sencilla y sin puntos de fallo compartidos:

```bash
# Ejecutar en CADA manager (master y workers)
cat << 'EOF' | sudo tee /etc/cron.d/edgewatch-dump-refresh
# Refresca el dump de Edgewatch cada 30 minutos
*/30 * * * * root TARGET_DIR=/var/ossec/integrations/edgewatch IP_EXPRESS_BIN=/usr/local/bin/ip-express /var/ossec/integrations/edgewatch-refresh-dump.sh >> /var/ossec/logs/edgewatch-refresh.log 2>&1
EOF
sudo chmod 644 /etc/cron.d/edgewatch-dump-refresh
```

> **Nota:** Como el dump se descarga de `raw.githubusercontent.com`, el hash SHA-256 es
> idéntico en todos los nodos. No hay inconsistencias entre managers.

#### Paso D — Reiniciar en todos los managers

```bash
# En cada manager, tras completar la instalación
sudo systemctl restart wazuh-manager
sudo systemctl status wazuh-manager
```

### Validación en clúster

```bash
# Verificar que CADA manager tiene el dump
ls -lh /var/ossec/integrations/edgewatch/latest.bin

# Verificar que el cron está activo en cada nodo
sudo cat /etc/cron.d/edgewatch-dump-refresh

# Verificar que la integración corre en cada manager (inyectar log de prueba en cada agente)
sudo tail -20 /var/ossec/logs/integrations.log | grep edgewatch
```

---

## 14. Recomendaciones de seguridad

- Mantén los scripts con `root:wazuh` y sin permisos de escritura para otros.
- Si tu política de red lo permite, restringe el acceso saliente solo a la URL del dump:
  `raw.githubusercontent.com`
- Monitoriza el log de refresco (`/var/ossec/logs/edgewatch-refresh.log`) y alerta si
  el checksum no cambia durante más de 24h (puede indicar fallo en la descarga).
- Revisa periódicamente que el número de entradas del dump crece con el tiempo
  (`ip-express info` muestra `DumpCount`).
