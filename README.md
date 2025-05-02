## 说明
原项目 https://github.com/aipeach/cloudflare-api-v4-ddns/blob/dev/cf-v4-ddns.sh

原项目使用文档参考 https://aipeach.gitbook.io/blogbackup/cloudflare-da-jian-ddns-jiao-ben-ban

变更：
- 使用cloudflare zone token，而不是account api key。
- 支持添加解析注释。

## 使用

### 下载脚本

```
curl https://raw.githubusercontent.com/aipeach/cloudflare-api-v4-ddns/master/cf-v4-ddns.sh > /root/cf-v4-ddns.sh && chmod +x /root/cf-v4-ddns.sh
```

### 修改脚本 补充信息

```
vim cf-v4-ddns.sh
```

```
# Create a token with Zone:DNS:Edit permissions for specific zones
# 为特定区域创建具有 Zone:DNS:Edit 权限的令牌
CFTOKEN=

# Zone ID, found in the Cloudflare dashboard overview page
# 区域 ID，可在 Cloudflare 仪表板概览页面右侧找到
CFZONE_ID=

# Hostname or subdomain to update, eg: homeserver or homeserver.example.com
# 通常填写需要使用的子域名
CFRECORD_NAME=

# Comment for the DNS record (optional)
# 选填 注释
CFRECORD_COMMENT=""
```

### 运行

首次运行脚本,输出内容会显示当前IP，进入cloudflare查看 确保IP已变更为当前IP

```
./cf-v4-ddns.sh
```

测试时，当nat ip 未变化时，可以强制刷新解析以查看更改

```
./cf-v4-ddns.sh -f true
```

添加定时任务

```
crontab -e
*/2 * * * * /root/cf-v4-ddns.sh >/dev/null 2>&1

# 如果需要日志，替换上一行代码
*/2 * * * * /root/cf-v4-ddns.sh >> /var/log/cf-ddns.log 2>&1
```

~~调试模式~~
~~`./script.sh -k "your_api_token" -i "your_zone_id" -h "subdomain" -d true`~~











----

Cloudflare API v4 Dynamic DNS Update in Bash, without unnecessary requests
Now the script also supports v6(AAAA DDNS Recoards)

----

创建 Cloudflare API 令牌，请转到 https://dash.cloudflare.com/profile/api-tokens 并按照以下步骤操作：

1. 单击创建令牌
2. 为令牌提供一个名称，例如，`cloudflare-ddns`
3. 授予令牌以下权限：
    * 区域 - 区域 - 读取
    * 区域 - 区域设置 - 读取
    * 区域 - DNS - 编辑
4. 将区域资源设置为：
    * 包括 - 特定区域 - 选择你想设置的域名

----
![image.png](https://i.loli.net/2021/11/13/OMpjhUyubrwN6Lk.png)

```
bash <(curl -Ls https://git.io/cloudflare-ddns) -k cloudflare-api-key \
 -h host.example.com \     # fqdn of the record you want to update
 -z example.com \          # will show you all zones if forgot, but you need this
 -t A|AAAA                 # specify ipv4/ipv6, default: ipv4
```
