# Конфигурация виртуальной машины devops-vm

Практическая работа № 5. Описание позволяет восстановить конфигурацию со снимка
`01-clean-install`; команды в разделах 4–6 выполняются в указанном порядке.

## 1. Параметры машины

| Параметр | Значение |
|---|---|
| Гипервизор | Oracle VirtualBox 7.2.20 (Windows 11) |
| Имя ВМ | `devops-vm` |
| Гостевая ОС | Ubuntu Server 24.04.5 LTS, ядро 6.8.0-142-generic |
| Оперативная память | 2048 МБ |
| Процессор | 2 ядра |
| Диск | 25 ГБ, VDI, динамически расширяемый; разметка «Use an entire disk» (без LVM) |
| Имя узла | `devops-vm`, FQDN `devops-vm.devops.local` |
| Особая настройка | HPET включён: `VBoxManage modifyvm devops-vm --hpet on --paravirt-provider kvm` (см. примечание) |

Примечание. На хосте активна защита на основе виртуализации (VBS), поэтому VirtualBox
работает поверх Hyper-V (режим NEM). Без HPET ядро гостя зависало на
`Loading essential drivers` или падало с `IO-APIC + timer doesn't work`. Снимки
создаются только на выключенной ВМ: «живой» снимок в режиме NEM зависает.

## 2. Сетевые интерфейсы

| Адаптер VirtualBox | Интерфейс в госте | Адрес | Назначение |
|---|---|---|---|
| 1 — NAT | `enp0s3` | `10.0.2.15/24` (DHCP) | выход в Интернет, репозитории пакетов, SSH через проброс порта |
| 2 — Host-only (`VirtualBox Host-Only Ethernet Adapter`) | `enp0s8` | `192.168.56.101/24` (DHCP) | прямой доступ с хоста, веб-сервер в ПР № 6 |

DHCP-сервер сети Host-only включён вручную (по умолчанию был выключен):

```powershell
VBoxManage dhcpserver modify --network="HostInterfaceNetworking-VirtualBox Host-Only Ethernet Adapter" `
  --server-ip=192.168.56.100 --netmask=255.255.255.0 `
  --lower-ip=192.168.56.101 --upper-ip=192.168.56.254 --enable
```

Netplan (`/etc/netplan/50-cloud-init.yaml`): `dhcp4: true` на `enp0s3` и `enp0s8`.

Полное доменное имя узла:

```bash
sudo hostnamectl set-hostname devops-vm
sudo sed -i 's/^127.0.1.1.*/127.0.1.1 devops-vm.devops.local devops-vm/' /etc/hosts
hostname -f        # devops-vm.devops.local
```

На хосте в `C:\Windows\System32\drivers\etc\hosts` добавлена строка:

```
192.168.56.101   devops.local
```

При включённом VPN (AmneziaVPN) трафик в `192.168.56.0/24` уходит в туннель:
на время работы по адресу Host-only VPN нужно выключить либо исключить эту подсеть.

## 3. Правило проброса портов

Адаптер 1 (NAT), правило `ssh`, протокол TCP:

| Этап | Адрес хоста | Порт хоста | Порт гостя |
|---|---|---|---|
| Снимок `01-clean-install` | 127.0.0.1 | 2222 | 22 |
| После задания 2 (текущее) | 127.0.0.1 | 2222 | 2222 |

```powershell
VBoxManage controlvm devops-vm natpf1 delete ssh
VBoxManage controlvm devops-vm natpf1 "ssh,tcp,127.0.0.1,2222,,2222"
```

## 4. Учётные записи

| Имя | UID | Группы | Способ аутентификации |
|---|---|---|---|
| `student` | 1000 | `student adm cdrom sudo dip plugdev lxd` | пароль, только локальная консоль (в SSH запрещён `AllowUsers`) |
| `devops` | 1001 | `devops sudo users` | SSH только по ключу ED25519; пароль нужен для `sudo` |

Создание `devops` (под `student`):

```bash
sudo adduser devops
sudo usermod -aG sudo devops
```

Ключ на хосте: `~/.ssh/devops_vm` (ED25519, комментарий `devops-vm-key`), отдельный
от ключа доступа к репозиториям. Размещение открытого ключа:

```bash
ssh-keygen -t ed25519 -C "devops-vm-key" -f ~/.ssh/devops_vm
ssh-copy-id -i ~/.ssh/devops_vm.pub -p 2222 devops@127.0.0.1
```

Права на сервере: `~/.ssh` — `700`, `~/.ssh/authorized_keys` — `600`.

`~/.ssh/config` на хосте:

```
Host devops
    HostName 127.0.0.1
    Port 2222
    User devops
    IdentityFile ~/.ssh/devops_vm
    IdentitiesOnly yes

Host devops.local
    Port 2222
    User devops
    IdentityFile ~/.ssh/devops_vm
    IdentitiesOnly yes
```

Отпечаток ключа хоста (сверен с `sudo ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub`):
`SHA256:OT40SlkV5yT4fjkMQhQWhUjtzRuMjGnrRZ2vzI+S+aI` (ED25519).

## 5. Служба SSH

Основной файл `/etc/ssh/sshd_config` не изменялся, эталонная копия —
`/etc/ssh/sshd_config.backup`. Изменения — в `/etc/ssh/sshd_config.d/99-hardening.conf`:

| Директива | Значение | Назначение |
|---|---|---|
| `Port` | `2222` | нестандартный порт |
| `PermitRootLogin` | `no` | запрет входа root |
| `PasswordAuthentication` | `no` | только ключи |
| `PubkeyAuthentication` | `yes` | вход по ключу |
| `PermitEmptyPasswords` | `no` | запрет пустых паролей |
| `MaxAuthTries` | `3` | попыток за соединение |
| `LoginGraceTime` | `30` | секунд на аутентификацию |
| `AllowUsers` | `devops` | единственный допустимый пользователь |
| `X11Forwarding` | `no` | без проброса X11 |
| `ClientAliveInterval` | `300` | проверка клиента, с |
| `ClientAliveCountMax` | `2` | разрыв после 2 неответов |

Конфликт: в `/etc/ssh/sshd_config.d/50-cloud-init.conf` (права `600`, виден только
через `sudo`) была строка `PasswordAuthentication yes`, которая читается раньше файла
`99-` и имеет приоритет. Строка закомментирована:

```bash
sudo sed -i 's/^PasswordAuthentication yes/#PasswordAuthentication yes/' /etc/ssh/sshd_config.d/50-cloud-init.conf
```

Проверка и переход с активации по сокету на обычную службу:

```bash
sudo sshd -t && echo "Конфигурация корректна"
sudo sshd -T | grep -Ei "^(port|permitrootlogin|passwordauthentication|maxauthtries|allowusers)"
sudo systemctl disable --now ssh.socket
sudo systemctl enable --now ssh.service
sudo systemctl restart ssh
sudo ss -tlnp | grep sshd        # 0.0.0.0:2222 и [::]:2222
```

После этого — изменить проброс портов (раздел 3). Итог: сервер принимает только
`publickey`.

## 6. Правила межсетевого экрана

UFW, журналирование `medium`. Разрешающие правила созданы до `ufw enable`.

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 80/tcp  comment 'HTTP'
sudo ufw allow 443/tcp comment 'HTTPS'
sudo ufw limit 2222/tcp comment 'SSH rate-limited'
sudo ufw --force enable
sudo ufw logging medium
```

| Порт | Действие | Комментарий |
|---|---|---|
| — | `deny (incoming)` | политика по умолчанию для входящих |
| — | `allow (outgoing)` | политика по умолчанию для исходящих |
| `2222/tcp` (v4, v6) | `LIMIT IN` | SSH; блокировка источника при ≥ 6 подключениях за 30 с |
| `80/tcp` (v4, v6) | `ALLOW IN` | HTTP, для ПР № 6 |
| `443/tcp` (v4, v6) | `ALLOW IN` | HTTPS |

## 7. Снимки состояния

Время — по Москве (UTC+3), 30.09.2026. Все снимки созданы на выключенной ВМ.

| Снимок | Создан | Состояние |
|---|---|---|
| `01-clean-install` | 15:01 | чистая установка, `apt upgrade`, OpenSSH на порту 22, проброс 2222→22 |
| `02-keys-configured` | 15:19 | пользователь `devops` в группе `sudo`, вход по ключу `devops_vm` |
| `03-ssh-hardened` | 15:29 | `99-hardening.conf`, sshd на 2222, `ssh.socket` отключён, проброс 2222→2222 |

Конфигурация после снимка `03-ssh-hardened` (UFW, FQDN) снимком не зафиксирована;
для полной проверки служит `scripts/audit.sh`:

```bash
scp scripts/audit.sh devops:~/ && ssh devops 'sudo bash ~/audit.sh'
```

## 8. Веб-сервер

Практическая работа № 6. Устанавливаемый пакет — `nginx` (Ubuntu 24.04, `apt install -y nginx`).
Главный процесс работает от `root`, рабочие — от `www-data`.

| Параметр | Значение |
|---|---|
| Конфигурация ресурса | `/etc/nginx/sites-available/devops-site`, активирована ссылкой в `/etc/nginx/sites-enabled/` |
| Стандартный ресурс | отключён (удалена ссылка `sites-enabled/default`, файл в `sites-available` сохранён) |
| Каталог ресурса | `/var/www/devops-site`, владелец `devops:devops`, каталоги `755`, файлы `644` |
| Сертификат | `/etc/ssl/certs/devops.crt`, права `644`, владелец `root` |
| Закрытый ключ | `/etc/ssl/private/devops.key`, права `600`, владелец `root` |
| Журналы | `/var/log/nginx/devops-site.access.log`, `/var/log/nginx/devops-site.error.log` |
| Протоколы TLS | `TLSv1.2 TLSv1.3`; заголовок HSTS не используется |

Порты 80 и 443 разрешены правилами из раздела 6; профили `ufw app` не применяются.

Формирование самоподписанного сертификата (срок действия — 365 суток, SAN `devops.local`):

```bash
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/private/devops.key \
  -out /etc/ssl/certs/devops.crt \
  -subj "/CN=devops.local" \
  -addext "subjectAltName=DNS:devops.local"
```

Каталог ресурса и конфигурация:

```bash
sudo mkdir -p /var/www/devops-site
sudo chown -R devops:devops /var/www/devops-site
sudo ln -s /etc/nginx/sites-available/devops-site /etc/nginx/sites-enabled/
sudo rm /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl reload nginx
```

Конфигурация `/etc/nginx/sites-available/devops-site`: блок `listen 80` с
`return 301 https://$host$request_uri;` и блок `listen 443 ssl` (IPv4 и IPv6) с
`server_name devops.local`, `root /var/www/devops-site`, `index index.html`,
`try_files $uri $uri/ =404`, `error_page 404 /404.html`, параметрами `ssl_certificate`,
`ssl_certificate_key`, `ssl_protocols` и отдельными журналами.

Содержимое доставляется из репозитория: `scripts/deploy.sh` (rsync с
`--delete --chmod=D755,F644`). На хосте сертификат для проверки клиентом сохранён в
`~/devops.crt` (`scp devops:/etc/ssl/certs/devops.crt ~/devops.crt`). Проверка конфигурации — раздел
`[4] Веб-сервер` в `scripts/audit.sh`.
