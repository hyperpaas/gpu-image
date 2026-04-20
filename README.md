# rgpu container image

这个仓库用于维护算力平台使用的容器镜像，以及对应的 GitHub Actions 构建/发布流程。

镜像目标：
- 基于 `debian:trixie-slim`
- 在 GitHub Actions 上直接构建
- 自动发布到 `ghcr.io/<owner>/<repo>`
- 提供 EasyTier + OpenSSH + OpenTelemetry Collector 的运行环境

## 镜像功能

镜像内包含：
- `tini`：作为容器 init，负责信号转发和僵尸进程回收
- `openssh-server`：支持 root 公钥登录
- `otelcol`：OpenTelemetry Collector
- `easytier-core`
- `easytier-cli`
- 基础工具：`curl`、`wget`、`vim`

容器启动顺序：
1. 检查 `ET_NETWORK_NAME` 和 `ET_NETWORK_SECRET`
2. 启动 EasyTier
3. 使用 `easytier-cli` 确认 EasyTier 已联网，并获取当前分配的 IPv4
4. 启动 `sshd`
5. 如果 `/etc/otelcol/config.yaml` 存在，则启动 `otelcol`；否则打印 warning 并跳过

当 EasyTier ready 后，entrypoint 会导出：

```text
ET_ASSIGNED_IPV4
```

该变量值为当前节点通过 EasyTier 获取到的内网 IPv4。

如果 `easytier-cli --output json node` 返回的 `config` 中检测到启用了 socks5 代理，entrypoint 还会导出：

```text
http_proxy
https_proxy
```

值来自 EasyTier 的 `socks5_proxy` 配置；如果监听地址是 `0.0.0.0`，会自动转成 `127.0.0.1` 供本容器内进程使用。

## SSH 说明

镜像中的 SSH 配置如下：
- 仅允许 root 登录
- 仅允许公钥认证
- 禁止密码登录

你可以通过两种方式提供 root 公钥：

### 方式 1：挂载 `authorized_keys`

将公钥文件挂载到：

```text
/root/.ssh/authorized_keys
```

可以使用只读挂载；entrypoint 会在文件可写时才尝试 `chmod 600`。

建议显式设置文件权限为 `0600`，避免 SSH 因权限过宽而忽略该文件。

### 方式 2：环境变量注入

设置环境变量：

```text
ROOT_AUTHORIZED_KEYS
```

内容就是完整的公钥文本。

## OpenTelemetry Collector 配置

Collector 配置文件固定路径：

```text
/etc/otelcol/config.yaml
```

约定：
- 如果该文件存在，容器启动时会拉起 `otelcol`
- 如果该文件不存在，容器仍然正常启动，只是不会启动 `otelcol`

这意味着在 Kubernetes 中可以直接通过 ConfigMap 挂载这个路径。

## EasyTier 环境变量

### 必填

- `ET_NETWORK_NAME`
- `ET_NETWORK_SECRET`

如果缺少任意一个，容器会直接启动失败。

### 常用可选项

以下环境变量会直接传给 `easytier-core` 读取，镜像本身不会再把它们拼成命令行参数：

- `ET_PEERS`
  - 逗号分隔
  - 例如：`tcp://1.2.3.4:11010,tcp://5.6.7.8:11010`
- `ET_LISTENERS`
  - 逗号分隔
  - 例如：`tcp://0.0.0.0:11010,udp://0.0.0.0:11010`
- `ET_MAPPED_LISTENERS`
- `ET_PROXY_NETWORKS`
- `ET_IPV4`
- `ET_NO_LISTENER`
- `ET_EXPECT_PEERS`
  - 用于增强 readiness 判断
- `ET_WAIT_TIMEOUT`
  - 默认 `120`
- `ET_POLL_INTERVAL`
  - 默认 `2`
- `ET_RPC_PORTAL`
  - 默认 `127.0.0.1:15888`
  - entrypoint 也会用它连接 `easytier-cli` 做 readiness 检查

### 运行时导出变量

- `ET_ASSIGNED_IPV4`
  - 不是输入变量
  - 由 entrypoint 在 EasyTier 联网成功后通过 `easytier-cli node` 查询得到并导出
- `http_proxy`
  - 当 EasyTier 配置了 socks5 代理时自动导出
- `https_proxy`
  - 当 EasyTier 配置了 socks5 代理时自动导出

## Docker 运行示例

下面是一个最小示例：

```bash
docker run -d \
  --name rgpu-node \
  --cap-add NET_ADMIN \
  --cap-add NET_RAW \
  --device /dev/net/tun:/dev/net/tun \
  -p 2222:22 \
  -p 11010:11010/tcp \
  -p 11010:11010/udp \
  -e ET_NETWORK_NAME=my-network \
  -e ET_NETWORK_SECRET=my-secret \
  -e ET_PEERS=tcp://1.2.3.4:11010 \
  -e ROOT_AUTHORIZED_KEYS="$(cat ~/.ssh/id_rsa.pub)" \
  ghcr.io/<owner>/<repo>:latest
```

说明：
- EasyTier 常见运行方式需要 `/dev/net/tun`
- 通常还需要 `NET_ADMIN`、`NET_RAW`
- 官方 Docker 示例更偏向 `--privileged` + `--network host`
- 如果你的用法不创建 TUN，可以按 EasyTier 参数自行收敛权限

## Kubernetes 部署说明

在 Kubernetes 中，建议重点关注以下几项：

### 1. EasyTier 权限

常见情况下需要：
- `/dev/net/tun`
- `NET_ADMIN`
- `NET_RAW`

如果你的 EasyTier 使用 TUN/VPN 模式，这是最常见的配置前提。

### 2. SSH 公钥

建议通过 Secret 挂载到：

```text
/root/.ssh/authorized_keys
```

如果当前只能使用 ConfigMap，也可以先用只读方式挂载到同一路径。

同样建议为挂载文件显式指定 `defaultMode: 0600`。

### 3. OTel Collector 配置

建议通过 ConfigMap 挂载到：

```text
/etc/otelcol/config.yaml
```

### 4. EasyTier 配置

通过 Pod 环境变量注入，例如：
- `ET_NETWORK_NAME`
- `ET_NETWORK_SECRET`
- `ET_PEERS`

### 5. 网络模式

EasyTier 官方容器示例偏向 host network。

在 Kubernetes 中是否使用 `hostNetwork: true`，取决于你的网络设计：
- 如果你希望更接近官方容器运行方式，可以考虑 `hostNetwork: true`
- 如果你只暴露必要端口，也可以先按普通 Pod 网络方式部署，再根据联通性调整

## Kubernetes 示例

下面示例演示：
- 通过 Secret 挂载 root SSH 公钥
- 通过 ConfigMap 挂载 OTel 配置
- 通过环境变量配置 EasyTier

> 注意：`/dev/net/tun` 的挂载方式、是否需要 `hostNetwork`、是否需要更高权限，和你的集群环境有关，下面示例仅提供基础参考。

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: rgpu-root-ssh
type: Opaque
stringData:
  authorized_keys: |
    ssh-ed25519 AAAA... your-key
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: rgpu-otelcol
data:
  config.yaml: |
    receivers:
      otlp:
        protocols:
          grpc:
          http:
    processors:
      batch:
    exporters:
      debug: {}
    service:
      pipelines:
        traces:
          receivers: [otlp]
          processors: [batch]
          exporters: [debug]
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: rgpu-node
spec:
  replicas: 1
  selector:
    matchLabels:
      app: rgpu-node
  template:
    metadata:
      labels:
        app: rgpu-node
    spec:
      containers:
        - name: rgpu-node
          image: ghcr.io/<owner>/<repo>:latest
          securityContext:
            capabilities:
              add:
                - NET_ADMIN
                - NET_RAW
          env:
            - name: ET_NETWORK_NAME
              value: my-network
            - name: ET_NETWORK_SECRET
              value: my-secret
            - name: ET_PEERS
              value: tcp://1.2.3.4:11010
          ports:
            - name: ssh
              containerPort: 22
            - name: easytier-tcp
              containerPort: 11010
              protocol: TCP
            - name: easytier-udp
              containerPort: 11010
              protocol: UDP
          volumeMounts:
            - name: ssh-auth
              mountPath: /root/.ssh/authorized_keys
              subPath: authorized_keys
              readOnly: true
            - name: otel-config
              mountPath: /etc/otelcol/config.yaml
              subPath: config.yaml
              readOnly: true
            - name: dev-net-tun
              mountPath: /dev/net/tun
      volumes:
        - name: ssh-auth
          secret:
            secretName: rgpu-root-ssh
            defaultMode: 0600
        - name: otel-config
          configMap:
            name: rgpu-otelcol
        - name: dev-net-tun
          hostPath:
            path: /dev/net/tun
            type: CharDevice
```

## GitHub Actions 发布规则

workflow 会构建并发布多架构镜像：
- `linux/amd64`
- `linux/arm64`

发布地址：

```text
ghcr.io/<owner>/<repo>
```

tag 规则：
- 默认分支 push：
  - `latest`
  - 默认分支名
  - `sha-<shortsha>`
- 非默认分支 push：
  - 分支名
  - `sha-<shortsha>`
- Git tag `vX.Y.Z`：
  - `X.Y.Z`
  - `X.Y`
  - `X`
  - `sha-<shortsha>`
- Pull Request：只构建校验，不推送

## 注意事项

### 1. EasyTier readiness

当前镜像会在启动 `sshd` 和 `otelcol` 前等待 EasyTier ready。

如果你的组网模式比较特殊，可以额外设置：

```text
ET_EXPECT_PEERS
```

来收紧 readiness 判定。

### 2. 停止行为

容器入口使用：

```text
tini -g
```

这有助于在 Pod 停止时把信号传播到整个子进程组。

但如果用户通过 SSH 执行了显式脱离会话的后台任务（例如 `nohup cmd &`），是否会被完全回收，仍取决于具体进程行为，不能只依赖 `tini -g`。

### 3. OTel 配置是可选的

如果你不需要 OpenTelemetry Collector，可以完全不挂载：

```text
/etc/otelcol/config.yaml
```

容器仍可正常运行。
