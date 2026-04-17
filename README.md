# 🚀 Pantheon PAWS API Installer

Jednostavan installer za deploy **PAWS API** na Linux server (Docker-based).

---

# 📦 Šta radi

* instalira Docker (ako nije instaliran)
* deploya PAWS API container
* generiše `appsettings.json`
* podržava:

  * Single DB mode
  * Host mode (multi-tenant)
* podržava:

  * `atNone`
  * `atToken`
  * `atUser`
* validira JSON prije deploya
* ima update script (safe upgrade)

---

# 🚀 Instalacija (1 komanda)

```bash
curl -sSL "https://raw.githubusercontent.com/emirhasanovic87-web/pantheon-paws-installer/main/install-paws.sh" | bash
```

---

# ⚙️ Tok instalacije

Installer pita:

* install folder
* Docker image
* port
* bind mode (localhost / private IP)
* DB mode:

  * Single database
  * Host mode
* AuthType
* SQL parametre

---

# 🧠 DB MODE

## 1️⃣ Single Database

Koristi se za:

* jedan klijent
* jedna baza

Koristi samo:

```json
PADBContext
```

---

## 2️⃣ Host Mode (Multi-tenant)

Koristi se za:

* više klijenata
* centralni `PAW_Master`

Koristi:

```json
PADBContext  → Pantheon user
HostsConnection → SQL user (PAW_Master)
```

---

# 🔐 AuthType

## atNone

✔ direktan pristup
✔ najjednostavnije
✔ radi odmah

👉 preporučeno za start

---

## atToken

✔ token-based auth
❗ zahtijeva dodatni flow

Redoslijed:

1. `authwithtoken`
2. `authsetDB`
3. business endpoint

---

## atUser

✔ user-based auth
(rjeđe korišten)

---

# 📄 appsettings.json pravila

## 🔴 OBAVEZNO

### 1. Linux

```json
"CustomCrypt": 1
```

---

### 2. Connection string format

```text
Data Source=IP,PORT;
```

NE:

```text
SERVER\INSTANCE
```

---

### 3. PADBContext

MORA sadržavati:

```text
MultipleActiveResultSets=True;
App=EntityFramework;
TrustServerCertificate=True;
Encrypt=False;
```

---

### 4. HostsConnection

MORA sadržavati:

```text
TrustServerCertificate=True;
Encrypt=False;
```

---

### 5. atToken pravilo

❗ Ako koristiš `atToken`:

```json
"HostsConnection" NE SMIJE biti prazan
```

---

# 🔄 Update

## Pokretanje

```bash
curl -sSL "https://raw.githubusercontent.com/emirhasanovic87-web/pantheon-paws-installer/main/update-paws.sh" | bash
```

---

## Šta radi

* backup `appsettings.json`
* validira JSON
* provjerava config
* pulla novi image
* redeploya container

---

# 🧪 Test API

```bash
curl http://127.0.0.1:8090/swagger/v1/swagger.json
```

---

# 🛠 Troubleshooting

## ❌ Error:

```
Format of the initialization string...
```

### Uzrok:

* prazan ili nevalidan connection string
* `HostsConnection=""` uz `atToken`
* neispravan format `Data Source`

---

## ❌ Token radi, endpoint ne radi

✔ problem je u token flow-u
✔ koristi `authsetDB`

---

## ❌ Container ne starta

```bash
docker compose logs -f
```

---

## ❌ JSON error

Installer ima validaciju:

```bash
python3 -m json.tool appsettings.json
```

---

# 🔧 Korisne komande

```bash
cd /opt/paws-api
docker compose logs -f
docker compose restart
docker compose down
docker compose ps
```

---

# 📌 Preporuka

Za početak:

```text
AuthType = atNone
```

Kad sve radi → prebaci na:

```text
atToken
```

---

# 🚀 Roadmap

* auto update (version check)
* healthcheck + rollback
* PAW_Master auto setup

---

# 👨‍💻 Autor


Emir Hasanovic
