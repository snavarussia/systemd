# Systemd

Проект для изучения **systemd**, systemd unit-файлов, timer, template units, FastCGI и запуска нескольких независимых экземпляров Apache HTTP Server.

Проект разворачивает виртуальную машину **CentOS Stream 9** с помощью **Vagrant + VirtualBox** и автоматически выполняет три практических задания:

1. Периодический мониторинг лог-файла с помощью `systemd timer`;
2. Запуск `spawn-fcgi` под управлением systemd;
3. Запуск нескольких независимых экземпляров Apache через template unit.

---

## Содержание

* [Технологии](#технологии)
* [Структура проекта](#структура-проекта)
* [Развёртывание](#развёртывание)
* [Задание 1 — systemd timer](#задание-1--systemd-timer)
* [Задание 2 — spawn-fcgi под systemd](#задание-2--spawn-fcgi-под-systemd)
* [Задание 3 — несколько экземпляров Apache](#задание-3--несколько-экземпляров-apache)
* [Проверка](#проверка)
* [Основные команды systemd](#основные-команды-systemd)
* [PID-файлы и `/var/run`](#pid-файлы-и-varrun)
* [SELinux](#selinux)
* [Что изучается в проекте](#что-изучается-в-проекте)
* [Важные замечания](#важные-замечания)

---

## Технологии

Проект использует:

* CentOS Stream 9;
* Vagrant;
* VirtualBox;
* systemd;
* systemd service units;
* systemd timer;
* systemd template units;
* Apache HTTP Server;
* `spawn-fcgi`;
* FastCGI;
* SELinux;
* Bash;
* DNF;
* `curl`;
* `ss`.

---

## Структура проекта

```text
systemd/
├── Vagrantfile
├── provision.sh
└── files/
    ├── log-monitor.service
    ├── log-monitor.timer
    ├── log-monitor.sh
    ├── log-monitor.sysconfig
    │
    ├── spawn-fcgi.service
    ├── spawn-fcgi.sysconfig
    ├── fcgi-testing
    │
    ├── httpd@.service
    ├── httpd-instance1.conf
    ├── httpd-instance2.conf
    │
    ├── index1.html
    └── index2.html
```

---

# Развёртывание

Для запуска проекта необходимы:

* VirtualBox;
* Vagrant;
* доступ к образу `centos/stream9`;
* доступ к исходному коду `spawn-fcgi`.

Запуск:

```bash
vagrant up
```

Vagrant создаст виртуальную машину:

```text
Hostname: systemd
IP:       192.168.56.10
RAM:      2048 MB
CPU:      1
OS:       CentOS Stream 9
```

Подключиться к виртуальной машине:

```bash
vagrant ssh
```

---

# Задание 1 — systemd timer

Первое задание демонстрирует периодический запуск сервиса с помощью `systemd timer`.

Используются три файла:

```text
log-monitor.service
log-monitor.timer
log-monitor.sh
```

Дополнительные параметры находятся в:

```text
/etc/sysconfig/log-monitor
```

Содержимое:

```bash
LOG_FILE="/var/log/messages"
KEYWORD="ERROR"
```

## `log-monitor.service`

Сервис имеет тип:

```ini
Type=oneshot
```

Это означает, что systemd запускает скрипт:

```text
/usr/local/bin/log-monitor.sh
```

Скрипт выполняет одну проверку и завершается.

После завершения процесса systemd считает выполнение сервиса законченным.

---

## `log-monitor.timer`

Timer запускает:

```text
log-monitor.service
```

Первый запуск выполняется через 10 секунд после загрузки:

```ini
OnBootSec=10s
```

После активации сервиса следующий запуск выполняется через 30 секунд:

```ini
OnUnitActiveSec=30s
```

Допустимое отклонение:

```ini
AccuracySec=1s
```

Таким образом, получается периодическая схема:

```text
systemd
   │
   ▼
log-monitor.timer
   │
   │ каждые 30 секунд
   ▼
log-monitor.service
   │
   ▼
log-monitor.sh
   │
   ▼
grep /var/log/messages
```

---

## Проверка timer

Посмотреть состояние:

```bash
systemctl status log-monitor.timer
```

Список активных timer:

```bash
systemctl list-timers
```

Посмотреть журнал сервиса:

```bash
journalctl -u log-monitor.service
```

Посмотреть последние сообщения:

```bash
journalctl -u log-monitor.service -n 20
```

---

# Задание 2 — spawn-fcgi под systemd

Второе задание показывает, как запускать FastCGI-приложение через systemd.

Используются:

```text
spawn-fcgi.service
spawn-fcgi.sysconfig
fcgi-testing
```

Конфигурация:

```bash
FCGI_ADDRESS=127.0.0.1
FCGI_PORT=9000
FCGI_PROGRAM=/usr/local/bin/fcgi-testing
```

В результате `spawn-fcgi` слушает:

```text
127.0.0.1:9000
```

---

## Почему `-n`

В unit используется:

```bash
/usr/local/bin/spawn-fcgi -n ...
```

Параметр `-n` запрещает переход `spawn-fcgi` в background.

Это важно для systemd.

Systemd должен иметь возможность непосредственно отслеживать основной процесс сервиса:

```text
systemd
   │
   ▼
spawn-fcgi
   │
   ▼
fcgi-testing
```

В unit используется:

```ini
Type=simple
```

---

## Автоматический перезапуск

В сервисе задано:

```ini
Restart=on-failure
RestartSec=2
```

Если процесс завершится с ошибкой, systemd через две секунды попробует запустить его снова.

---

## Проверка

Состояние:

```bash
systemctl status spawn-fcgi.service
```

Порт:

```bash
ss -lntp
```

Ожидается:

```text
127.0.0.1:9000
```

Логи:

```bash
journalctl -u spawn-fcgi.service
```

---

# Задание 3 — несколько экземпляров Apache

Третье задание демонстрирует **template unit systemd**.

Используется один unit:

```text
httpd@.service
```

На его основе создаются два независимых экземпляра:

```text
httpd@instance1.service
httpd@instance2.service
```

Systemd подставляет значение экземпляра вместо `%i`.

Например:

```text
httpd@instance1.service
```

превращается в:

```text
%i = instance1
```

А:

```text
httpd@instance2.service
```

превращается в:

```text
%i = instance2
```

Это позволяет использовать один шаблон для нескольких экземпляров приложения.

---

## Архитектура

```text
                  systemd
                     │
             ┌───────┴────────┐
             │                │
             ▼                ▼
 httpd@instance1.service  httpd@instance2.service
             │                │
             ▼                ▼
        Apache #1          Apache #2
             │                │
             ▼                ▼
         TCP 8081          TCP 8082
             │                │
             ▼                ▼
    /var/www/instance1  /var/www/instance2
```

---

## Первый экземпляр

Конфигурация:

```text
/etc/httpd/conf.d/httpd-instance1.conf
```

Порт:

```text
8081
```

DocumentRoot:

```text
/var/www/instance1
```

Страница:

```text
/var/www/instance1/index.html
```

Проверка:

```bash
curl http://127.0.0.1:8081/
```

Результат:

```html
<h1>Apache Instance 1</h1>
```

---

## Второй экземпляр

Конфигурация:

```text
/etc/httpd/conf.d/httpd-instance2.conf
```

Порт:

```text
8082
```

DocumentRoot:

```text
/var/www/instance2
```

Страница:

```text
/var/www/instance2/index.html
```

Проверка:

```bash
curl http://127.0.0.1:8082/
```

Результат:

```html
<h1>Apache Instance 2</h1>
```

---

# Проверка

После выполнения:

```bash
vagrant up
```

можно подключиться к VM:

```bash
vagrant ssh
```

Проверить все необходимые процессы:

```bash
systemctl --no-pager --full status log-monitor.timer
systemctl --no-pager --full status spawn-fcgi.service
systemctl --no-pager --full status httpd@instance1.service
systemctl --no-pager --full status httpd@instance2.service
```

Проверить сетевые порты:

```bash
ss -lntp
```

Должны использоваться:

```text
8081  Apache instance1
8082  Apache instance2
9000  spawn-fcgi
```

Проверить HTTP:

```bash
curl -f http://127.0.0.1:8081/
curl -f http://127.0.0.1:8082/
```

Проверить timer:

```bash
systemctl list-timers
```

Проверить журнал:

```bash
journalctl -u log-monitor.service
journalctl -u spawn-fcgi.service
journalctl -u httpd@instance1.service
journalctl -u httpd@instance2.service
```

---

# Основные команды systemd

## Перечитать unit-файлы

После добавления или изменения unit-файлов:

```bash
systemctl daemon-reload
```

Это необходимо, чтобы systemd перечитал конфигурацию unit-файлов. Red Hat также рекомендует выполнять `daemon-reload` после создания или изменения unit-файлов.

---

## Запуск

```bash
systemctl start httpd@instance1.service
```

---

## Остановка

```bash
systemctl stop httpd@instance1.service
```

---

## Перезапуск

```bash
systemctl restart httpd@instance1.service
```

---

## Автозапуск

```bash
systemctl enable httpd@instance1.service
```

---

## Включить и сразу запустить

```bash
systemctl enable --now httpd@instance1.service
```

---

## Проверить статус

```bash
systemctl status httpd@instance1.service
```

---

# PID-файлы и `/var/run`

В проекте PID-файлы Apache находятся в:

```text
/var/run/httpd-instance1/httpd.pid
/var/run/httpd-instance2/httpd.pid
```

Например:

```apache
PidFile "/var/run/httpd-instance1/httpd.pid"
```

### Важное замечание

Для современных Linux-систем при создании **новой конфигурации** предпочтительнее использовать:

```text
/run
```

а не:

```text
/var/run
```

Причина в том, что `/run` является современным стандартным расположением для runtime-данных системы: PID-файлов, transient UNIX sockets и других данных, существующих только в течение текущей загрузки системы. FHS прямо указывает, что функции `/var/run` были перенесены в `/run`, а `/var/run` оставлен для совместимости.

На современных системах обычно:

```text
/var/run -> /run
```

Поэтому использование `/var/run` в данном проекте работает, но для нового проекта предпочтительнее:

```apache
PidFile "/run/httpd-instance1/httpd.pid"
```

и:

```apache
PidFile "/run/httpd-instance2/httpd.pid"
```

### Ещё лучше — использовать возможности systemd

Для systemd-сервиса runtime-каталог можно создавать средствами самого systemd, например через:

```ini
RuntimeDirectory=httpd-instance1
```

В template unit можно использовать `%i`, поэтому концептуально можно организовать:

```ini
RuntimeDirectory=httpd-%i
```

а в Apache использовать:

```apache
PidFile "/run/httpd-%i/httpd.pid"
```

Это позволяет не создавать runtime-каталоги вручную через:

```bash
mkdir -p /var/run/...
```

и связывает жизненный цикл runtime-каталога с жизненным циклом systemd-сервиса.

Systemd также предоставляет спецификатор `%t`, который для системных сервисов соответствует `/run`.

> **Примечание:** в текущей версии проекта `/var/run` намеренно оставлен в конфигурации как часть примера. При дальнейшей модернизации проекта его стоит заменить на `/run` и поручить systemd создание runtime-каталогов.

---

# SELinux

CentOS Stream 9 использует SELinux.

Apache в проекте слушает нестандартные HTTP-порты:

```text
8081
8082
```

SELinux должен знать, что эти TCP-порты разрешено использовать HTTP-сервисам.

Для этого provisioning выполняет:

```bash
semanage port -a -t http_port_t -p tcp 8081
semanage port -a -t http_port_t -p tcp 8082
```

Если порт уже существует в политике SELinux, используется:

```bash
semanage port -m
```

После настройки можно проверить:

```bash
semanage port -l | grep http_port_t
```

---

# Особенности Apache template unit

Основной unit:

```text
httpd@.service
```

Запуск:

```bash
systemctl start httpd@instance1.service
```

Systemd подставляет:

```text
instance1
```

вместо:

```text
%i
```

Поэтому выполняется:

```bash
/usr/sbin/httpd -DFOREGROUND -f /etc/httpd/conf.d/httpd-instance1.conf
```

Для второго экземпляра:

```bash
/usr/sbin/httpd -DFOREGROUND -f /etc/httpd/conf.d/httpd-instance2.conf
```

Таким образом, оба Apache используют один systemd template unit, но разные конфигурационные файлы.

---

# Почему Apache запускается в foreground

В unit используется:

```ini
Type=simple
```

и:

```bash
httpd -DFOREGROUND
```

Это позволяет systemd непосредственно отслеживать процесс Apache.

Схема:

```text
systemd
   │
   └── httpd -DFOREGROUND
             │
             └── Apache workers
```

Вместо самостоятельного ухода Apache в background systemd остаётся владельцем жизненного цикла сервиса.

---

# `PrivateTmp=true`

В Apache unit используется:

```ini
PrivateTmp=true
```

Это означает, что экземпляр сервиса получает собственное изолированное представление временных каталогов `/tmp` и `/var/tmp`.

Таким образом, временные файлы Apache не находятся непосредственно в общем `/tmp` других процессов.

---

# Важное замечание о `/etc/httpd/conf.d`

В проекте конфигурации экземпляров устанавливаются в:

```text
/etc/httpd/conf.d/
```

Однако запуск каждого экземпляра выполняется с явным указанием:

```bash
-f /etc/httpd/conf.d/httpd-instance1.conf
```

и:

```bash
-f /etc/httpd/conf.d/httpd-instance2.conf
```

Это сделано намеренно для примера: каждый экземпляр получает собственный основной конфигурационный файл.

---

# Важное замечание о proxy

В `provision.sh` используется переменная:

```bash
GIT_PROXY="http://username:password@proxy.example.com:8080"
```

Это демонстрационный пример.

**Не следует хранить реальные логины и пароли от proxy непосредственно в Git-репозитории.**

Для реального проекта credentials лучше передавать отдельно, например через:

* Переменные окружения;
* Локальный конфигурационный файл, не попадающий в Git;
* Credential helper;
* Секрет-хранилище.

Например, сам принцип можно реализовать через:

```bash
git -c http.proxy="$GIT_PROXY" clone ...
```

при этом значение `GIT_PROXY` должно поступать извне репозитория.

---

# Что изучается в проекте

Проект позволяет на практике отработать следующие концепции systemd:

### Service

Создание собственного:

```text
.service
```

и управление им:

```bash
systemctl start
systemctl stop
systemctl restart
systemctl status
```

### Timer

Периодический запуск:

```text
.timer
```

вместо классического cron.

### `Type=oneshot`

Использование systemd для запуска задачи, которая выполняется один раз и завершается.

### `Type=simple`

Запуск долгоживущего foreground-процесса, которым непосредственно управляет systemd.

### `Restart=on-failure`

Автоматический перезапуск упавшего процесса.

### EnvironmentFile

Передача конфигурации сервису через:

```ini
EnvironmentFile=
```

### Template units

Создание нескольких экземпляров одного сервиса:

```text
httpd@instance1.service
httpd@instance2.service
```

на основе:

```text
httpd@.service
```

### `%i`

Использование идентификатора экземпляра внутри template unit.

### SELinux

Разрешение Apache использовать нестандартные TCP-порты.

### `daemon-reload`

Перечитывание конфигурации systemd после изменения unit-файлов.

### `journalctl`

Просмотр журнала работы сервисов.

### Vagrant provisioning

Автоматическая установка и настройка всей лабораторной среды.

---

# Итоговая схема проекта

```text
                         CentOS Stream 9
                               │
                               │
                            systemd
                               │
          ┌────────────────────┼────────────────────┐
          │                    │                    │
          ▼                    ▼                    ▼
 log-monitor.timer      spawn-fcgi.service    httpd@.service
          │                    │                    │
          ▼                    ▼             ┌──────┴──────┐
 log-monitor.service       spawn-fcgi        │             │
          │                    │              ▼             ▼
          ▼                    ▼        instance1       instance2
   log-monitor.sh         FastCGI app         │             │
          │                    │              ▼             ▼
          ▼                    ▼           :8081         :8082
 /var/log/messages        127.0.0.1:9000      │             │
                                               ▼             ▼
                                      /var/www/instance1
                                                        /instance2
```

---

## Результат

После выполнения:

```bash
vagrant up
```

в системе работают:

```text
log-monitor.timer
        │
        └── log-monitor.service

spawn-fcgi.service
        │
        └── FastCGI :9000

httpd@instance1.service
        │
        └── Apache :8081

httpd@instance2.service
        │
        └── Apache :8082
```

Проект представляет собой небольшую лабораторию, в которой на одном сервере можно последовательно изучить **systemd services, timers, template units, foreground processes, environment files, restart policies, SELinux и управление несколькими экземплярами одного приложения**.
