% base
...
creator s64 : 创建者
create_time t + : 创建时间
updater s64 : 更新者
update_time t ++ : 更新时间
deleted b =0 : 是否删除

% base2 > base
...
status n : 部门状态（0正常 1停用）
tenant_id N =0 : 租户编号

% base3 > base2
...
client_id : 客户端编号
scopes : 授权范围
expires_time t : 过期时间

% base4 > base2
...
user_ip s50 : 用户 IP
user_agent s512 : 浏览器 UA

% base5 > base2
...
params : 参数数组
remark : 备注

# base4 infra_api_access_log : API 访问日志表
id N ++ : 日志主键
trace_id s64 : 链路追踪编号
user_id N =0 : 用户编号
user_type n =0 : 用户类型
application_name s50 : 应用名
request_method s16 : 请求方法名
request_url : 请求地址
request_params S : 请求参数
response_body S : 响应结果
operate_module s50 : 操作模块
operate_name s50 : 操作名
operate_type n =0 : 操作分类
begin_time t : 开始请求时间
end_time t : 结束请求时间
duration n : 执行时长
result_code n =0 : 结果码
result_msg s512 : 结果提示

# base4 infra_api_error_log : 系统异常日志
id N ++ : 编号
trace_id s64 : 链路追踪编号
user_id N =0 : 用户编号
user_type n =0 : 用户类型
application_name s50 : 应用名
request_method s16 : 请求方法名
request_url : 请求地址
request_params s8000 : 请求参数
exception_time t : 异常发生时间
exception_name s128 : 异常名
exception_message S : 异常导致的消息
exception_root_cause_message S : 异常导致的根消息
exception_stack_trace S : 异常的栈轨迹
exception_class_name s512 : 异常发生的类全名
exception_file_name s512 : 异常发生的类文件
exception_method_name s512 : 异常发生的方法名
exception_line_number n : 异常发生的方法所在行
process_status n : 处理状态
process_time t : 处理时间
process_user_id =0 : 处理用户编号

# base infra_codegen_column : 代码生成表字段定义
id N ++ : 编号
table_id N @ : 表编号
column_name s200 : 字段名
data_type s100 : 字段类型
column_comment s500 : 字段描述
nullable b : 是否允许为空
primary_key b : 是否主键
ordinal_position n : 排序
java_type s32 : Java 属性类型
java_field s64 : Java 属性名
dict_type s200 : 字典类型
example s64 : 数据示例
create_operation b : 是否为 Create 创建操作的字段
update_operation b : 是否为 Update 更新操作的字段
list_operation b : 是否为 List 查询操作的字段
list_operation_condition s32 == : List 查询操作的条件类型
list_operation_result b : 是否为 List 查询操作的返回字段
html_type s32 : 显示类型

# base infra_codegen_table : 代码生成表定义
id N ++ : 编号
data_source_config_id N : 数据源配置的编号
scene n =1 : 生成场景
table_name s200 : 表名称
table_comment s500 : 表描述
remark s500 : 备注
module_name s30 : 模块名
business_name s30 : 业务名
class_name s100 : 类名称
class_comment s50 : 类描述
author s50 : 作者
template_type n =1 : 模板类型
front_type n : 前端类型
parent_menu_id N : 父菜单编号
master_table_id N : 主表的编号
sub_join_column_id N : 子表关联主表的字段编号
sub_join_many b : 主表与子表是否一对多
tree_parent_column_id N : 树表的父字段编号
tree_name_column_id N : 树表的名字字段编号

# base infra_config : 参数配置表
id N ++ : 参数主键
category s50 : 参数分组
type n : 参数类型
name s100 : 参数名称
config_key s100 @ : 参数键名
value s500 : 参数键值
visible b : 是否可见
remark s500 : 备注

# base infra_data_source_config : 数据源配置表
id N ++ : 主键编号
name s100 : 参数名称
url s1024 : 数据源连接
username : 用户名
password : 密码

# base infra_file : 文件表
id N ++ : 文件编号
config_id N : 配置编号
name s256 : 文件名
path s512 : 文件路径
url s1024 : 文件 URL
type s128 : 文件类型
size n : 文件大小

# base infra_file_config : 文件配置表
id N ++ : 编号
name s63 : 配置名
storage n : 存储器
remark : 备注
master b : 是否为主配置
config s4096 : 存储配置

# base infra_file_content : 文件表
id N ++ : 编号
config_id N : 配置编号
path s512 : 文件路径
content B : 文件内容

@ config_id path
# base infra_job : 定时任务表
id N ++ : 任务编号
name s32 : 任务名称
status n : 任务状态
handler_name s64 : 处理器的名字
handler_param : 处理器的参数
cron_expression s32 : CRON 表达式
retry_count n =0 : 重试次数
retry_interval n =0 : 重试间隔
monitor_timeout n =0 : 监控超时时间

# base infra_job_log : 定时任务日志表
id N ++ : 日志编号
job_id N @ : 任务编号
handler_name s64 : 处理器的名字
handler_param : 处理器的参数
execute_index n =1 : 第几次执行
begin_time t : 开始执行时间
end_time t : 结束执行时间
duration n : 执行时长
status n : 任务状态
result s4000 : 结果数据

# base2 system_dept : 部门表
id N ++ : 部门id
name s30 : 部门名称
parent_id N =0 : 父部门id
sort n =0 : 显示顺序
leader_user_id N : 负责人
phone s11 : 联系电话
email s50 : 邮箱

# base system_dict_data : 字典数据表
id N ++ : 字典编码
sort n =0 : 字典排序
label s100 : 字典标签
value s100 : 字典键值
dict_type s100 : 字典类型
status n =0 : 状态（0正常 1停用）
color_type s100 : 颜色类型
css_class s100 : css 样式
remark s500 : 备注

# base system_dict_type : 字典类型表
id N ++ : 字典主键
name s100 : 字典名称
type s100 : 字典类型
status n =0 : 状态（0正常 1停用）
remark s500 : 备注
deleted_time t : 删除时间

# base4 system_login_log : 系统访问记录
id N ++ : 访问ID
log_type N : 日志类型
trace_id s64 : 链路追踪编号
user_id N =0 : 用户编号
user_type n =0 : 用户类型
username s50 @ : 用户账号
result n : 登陆结果

# base system_mail_account : 邮箱账号表
id N ++ : 主键
mail : 邮箱
username : 用户名
password : 密码
host : SMTP 服务器域名
port n : SMTP 服务器端口
ssl_enable b =0 : 是否开启 SSL
starttls_enable b =0 : 是否开启 STARTTLS

# base system_mail_log : 邮件日志表
id N ++ : 编号
user_id N : 用户编号
user_type n : 用户类型
to_mails s1024 : 接收邮箱地址
cc_mails s1024 : 抄送邮箱地址
bcc_mails s1024 : 密送邮箱地址
account_id N : 邮箱账号编号
from_mail : 发送邮箱地址
template_id N : 模板编号
template_code s63 : 模板编码
template_nickname : 模版发送人名称
template_title : 邮件标题
template_content S : 邮件内容
template_params : 邮件参数
send_status n =0 : 发送状态
send_time t : 发送时间
send_message_id : 发送返回的消息 ID
send_exception s4096 : 发送异常

# base5 system_mail_template : 邮件模版表
id N ++ : 编号
name s63 : 模板名称
code s63 : 模板编码
account_id N : 发送的邮箱账号编号
nickname : 发送人名称
title : 模板标题
content s10240 : 模板内容

# base system_menu : 菜单权限表
id N ++ : 菜单ID
name s50 : 菜单名称
permission s100 : 权限标识
type n : 菜单类型
sort n =0 : 显示顺序
parent_id N =0 : 父菜单ID
path s200 : 路由地址
icon s100 =# : 菜单图标
component : 组件路径
component_name : 组件名
status n =0 : 菜单状态
visible b =1 : 是否可见
keep_alive b =1 : 是否缓存
always_show b =1 : 是否总是显示

# base2 system_notice : 通知公告表
id N ++ : 公告ID
title s50 : 公告标题
content S : 公告内容
type n : 公告类型（1通知 2公告）

# base system_notify_message : 站内信消息表
id N ++ : 用户ID
user_id N : 用户id
user_type n : 用户类型
template_id N : 模版编号
template_code s64 : 模板编码
template_nickname s63 : 模版发送人名称
template_content s1024 : 模版内容
template_type n : 模版类型
template_params : 模版参数
read_status b : 是否已读
read_time t : 阅读时间
tenant_id N =0 : 租户编号

@ user_id user_type read_status
# base5 system_notify_template : 站内信模板表
id N ++ : 主键
name s63 : 模板名称
code s64 : 模版编码
nickname : 发送人名称
content s1024 : 模版内容
type n : 类型

# base3 system_oauth2_access_token : OAuth2 访问令牌
id N ++ : 编号
user_id N : 用户编号
user_type n : 用户类型
user_info s512 : 用户信息
access_token @ : 访问令牌
refresh_token s32 @ : 刷新令牌

# base system_oauth2_approve : OAuth2 批准表
id N ++ : 编号
user_id N : 用户编号
user_type n : 用户类型
client_id : 客户端编号
scope : 授权范围
approved b =0 : 是否接受
expires_time t : 过期时间
tenant_id N =0 : 租户编号

@ user_id user_type client_id
# base system_oauth2_client : OAuth2 客户端表
id N ++ : 编号
client_id @ : 客户端编号
secret : 客户端密钥
name : 应用名
logo : 应用图标
description : 应用描述
status n : 状态
access_token_validity_seconds n : 访问令牌的有效期
refresh_token_validity_seconds n : 刷新令牌的有效期
redirect_uris : 可重定向的 URI 地址
authorized_grant_types : 授权类型
scopes : 授权范围
auto_approve_scopes : 自动通过的授权范围
authorities : 权限
resource_ids : 资源
additional_information s4096 : 附加信息

# base3 system_oauth2_code : OAuth2 授权码表
id N ++ : 编号
user_id N : 用户编号
user_type n : 用户类型
code s32 @ : 授权码
redirect_uri : 可重定向的 URI 地址
state : 状态

# base3 system_oauth2_refresh_token : OAuth2 刷新令牌
id N ++ : 编号
user_id N : 用户编号
refresh_token s32 @ : 刷新令牌
user_type n : 用户类型

# base4 system_operate_log : 操作日志记录 V2 版本
id N ++ : 日志主键
trace_id s64 : 链路追踪编号
user_id N @ : 用户编号
user_type n =0 : 用户类型
type s50 : 操作模块类型
sub_type s50 : 操作名
biz_id N : 操作数据模块编号
action s2000 : 操作内容
success b =1 : 操作结果
extra s2000 : 拓展字段
request_method s16 : 请求方法名
request_url : 请求地址

# base2 system_post : 岗位信息表
id N ++ : 岗位ID
code s64 : 岗位编码
name s50 : 岗位名称
sort n : 显示顺序
remark s500 : 备注

# base2 system_role : 角色信息表
id N ++ : 角色ID
name s30 : 角色名称
code s100 : 角色权限字符串
sort n : 显示顺序
data_scope n =1 : 数据范围（1：全部数据权限 2：自定数据权限 3：本部门数据权限 4：本部门及以下数据权限）
data_scope_dept_ids s500 : 数据范围(指定部门数组)
type n : 角色类型
remark s500 : 备注

# base system_role_menu : 角色和菜单关联表
id N ++ : 自增编号
role_id N @ : 角色ID
menu_id N : 菜单ID
tenant_id N =0 : 租户编号

# base system_sms_channel : 短信渠道
id N ++ : 编号
signature s12 : 短信签名
code s63 : 渠道编码
status n : 开启状态
remark : 备注
api_key s128 : 短信 API 的账号
api_secret s128 : 短信 API 的秘钥
callback_url : 短信发送回调 URL

# base system_sms_code : 手机验证码
id N ++ : 编号
mobile s11 @ : 手机号
code s6 : 验证码
create_ip s15 : 创建 IP
scene n : 发送场景
today_index n : 今日发送的第几条
used n : 是否使用
used_time t : 使用时间
used_ip : 使用 IP
tenant_id N =0 : 租户编号

# base system_sms_log : 短信日志
id N ++ : 编号
channel_id N : 短信渠道编号
channel_code s63 : 短信渠道编码
template_id N : 模板编号
template_code s63 : 模板编码
template_type n : 短信类型
template_content : 短信内容
template_params : 短信参数
api_template_id s63 : 短信 API 的模板编号
mobile s11 : 手机号
user_id N : 用户编号
user_type n : 用户类型
send_status n =0 : 发送状态
send_time t : 发送时间
api_send_code s63 : 短信 API 发送结果的编码
api_send_msg : 短信 API 发送失败的提示
api_request_id : 短信 API 发送返回的唯一请求 ID
api_serial_no : 短信 API 发送返回的序号
receive_status n =0 : 接收状态
receive_time t : 接收时间
api_receive_code s63 : API 接收结果的编码
api_receive_msg : API 接收结果的说明

# base5 system_sms_template : 短信模板
id N ++ : 编号
type n : 模板类型
code s63 : 模板编码
name s63 : 模板名称
content : 模板内容
api_template_id s63 : 短信 API 的模板编号
channel_id N : 短信渠道编号
channel_code s63 : 短信渠道编码

# base2 system_social_client : 社交客户端表
id N ++ : 编号
name : 应用名
social_type n : 社交平台的类型
user_type n : 用户类型
client_id : 客户端编号
client_secret : 客户端密钥
agent_id : 代理编号
public_key s2048 : publicKey 公钥

# base system_social_user : 社交用户表
id N ++ : 主键(自增策略)
type n : 社交平台的类型
openid s32 : 社交 openid
token s256 : 社交 token
raw_token_info s1024 : 原始 Token 数据，一般是 JSON 格式
nickname s32 : 用户昵称
avatar : 用户头像
raw_user_info s1024 : 原始用户数据，一般是 JSON 格式
code s256 : 最后一次的认证 code
state s256 : 最后一次的认证 state
tenant_id N =0 : 租户编号

@ type openid
@ type code state
# base system_social_user_bind : 社交绑定表
id N ++ : 主键(自增策略)
user_id N : 用户编号
user_type n : 用户类型
social_type n : 社交平台的类型
social_user_id N : 社交用户的编号
tenant_id N =0 : 租户编号

@ user_type social_user_id
# base system_tenant : 租户表
id N ++ : 租户编号
name s30 : 租户名
contact_user_id N : 联系人的用户编号
contact_name s30 : 联系人
contact_mobile s500 : 联系手机
status n =0 : 租户状态
websites s1024 : 绑定域名数组
package_id N : 租户套餐编号
expire_time t : 过期时间
account_count n : 账号数量

# base system_tenant_package : 租户套餐表
id N ++ : 套餐编号
name s30 : 套餐名
status n =0 : 租户状态（0正常 1停用）
remark s256 : 备注
menu_ids s4096 : 关联的菜单编号

# base system_user_post : 用户岗位表
id N ++ : id
user_id N =0 : 用户ID
post_id N =0 : 岗位ID
tenant_id N =0 : 租户编号

# base system_user_role : 用户和角色关联表
id N ++ : 自增编号
user_id N @ : 用户ID
role_id N : 角色ID
tenant_id N =0 : 租户编号

# base2 system_users : 用户信息表
id N ++ : 用户ID
username s30 @ : 用户账号
password s100 : 密码
nickname s30 : 用户昵称
remark s500 : 备注
dept_id N @ : 部门ID
post_ids : 岗位编号数组
email s50 @ : 用户邮箱
mobile s11 @ : 手机号码
sex n =0 : 用户性别
avatar s512 : 头像地址
login_ip s50 : 最后登录IP
login_date t : 最后登录时间
