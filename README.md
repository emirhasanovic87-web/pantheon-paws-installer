# 🐳 Pantheon PAWS API – Linux Installer

Jednostavan i standardiziran način za deployment PAWS API-a na Linux server koristeći Docker.

---

# 🚀 Quick Install

curl -sSLo install-paws.sh https://raw.githubusercontent.com/emirhasanovic87-web/pantheon-paws-installer/main/install-paws.sh
chmod +x install-paws.sh
./install-paws.sh

---

# 🔄 Update

./update-paws.sh

---

# 🐧 Supported Platforms

- Ubuntu
- Debian

Za ostale Linux distribucije potrebno je ručno instalirati Docker i Docker Compose plugin.

---

# ⚙️ Šta installer radi

Installer automatski:

- instalira Docker (ako nije instaliran)
- instalira Docker Compose plugin
- povlači PAWS API Docker image
- kreira docker-compose.yml
- kreira appsettings.json template (ako ne postoji)
- pokreće container

---

# 🌐 Način pristupa

Installer nudi dvije opcije:

## 1. Localhost (preporučeno)

127.0.0.1:PORT

Idealno za:
- Cloudflare Tunnel
- reverse proxy
- sigurnu produkciju

## 2. Private IP

PRIVATE_IP:PORT

Idealno za:
- LAN pristup
- VPN 
- internu mrežu

---

# 🔐 Sigurnosna preporuka

Preporučeni setup:

- koristiti localhost bind (127.0.0.1)
- izložiti servis preko Cloudflare Tunnel-a
- ne otvarati direktno port prema internetu

---

# 📦 Konfiguracija

Nakon instalacije potrebno je urediti:

/opt/paws-api/appsettings.json

Primjer:

{
  "ConnectionStrings": {
    "PADBContext": "Server=SQL_IP,PORT;Database=DB_NAME;User ID=USER;Password=PASSWORD;TrustServerCertificate=True;Encrypt=False"
  },
  "AppSettings": {
    "CustomCrypt": 1
  }
}

---

# 🧪 Test

curl http://127.0.0.1:8090/swagger/v1/swagger.json

ili u browseru:

http://SERVER_IP:PORT/swagger/index.html

---

# 🛠️ Korisne komande

cd /opt/paws-api

docker compose logs -f
docker compose restart
docker compose down

---

# 🚀 Prednosti Linux Docker deploy-a

U odnosu na Windows IIS:

- brži deployment (par minuta)
- jednostavna instalacija , napravljen installer script ( 1 komanda)
- jednostavan update (1 komanda)
- sigurniji (localhost + Cloudflare)
- niži troškovi (bez Windows licence)
- standardizovan deployment (Docker)
- brži recovery (restart u par sekundi)

---

# 📌 Napomena

Installer je interaktivan i ne preporučuje se pokretanje direktno sa:

curl ... | bash

Umjesto toga koristiti:

curl -O install-paws.sh
bash install-paws.sh

---

# 🧾 Verzije

Docker image koristi verzionisanje:

10.47.10
10.47.11
latest

---

# 👨‍💻 Autor

Emir Hasanovic