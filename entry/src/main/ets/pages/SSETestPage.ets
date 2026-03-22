/**
 * SSE Test Page
 * 用于验证HarmonyOS对Server-Sent Events的支持
 */
import { http } from '@kit.NetworkKit'
import { router } from '@kit.ArkUI'
import { BusinessError } from '@kit.BasicServicesKit'
import { util } from '@kit.ArkTS'

// SSE响应数据类型
interface SSEDictData {
  type: string
  content: string | SSEExampleData | null
}

interface SSEExampleData {
  ko: string
  zh: string
}

@Entry
@Component
struct SSETestPage {
  @State simpleResult: string = ''
  @State dictResult: string = ''
  @State isSimpleTesting: boolean = false
  @State isDictTesting: boolean = false
  @State simpleStatus: string = '未测试'
  @State dictStatus: string = '未测试'
  @State serverUrl: string = 'http://192.168.1.59:8000'

  build() {
    Column() {
      // 标题栏
      Row() {
        Image($r('app.media.ic_back'))
          .width(24)
          .height(24)
          .margin({ right: 16 })
          .onClick(() => router.back())

        Text('SSE 支持测试')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
      }
      .width('100%')
      .padding(16)

      Scroll() {
        Column() {
          // 服务器地址配置
          Column() {
            Text('服务器地址')
              .fontSize(14)
              .fontColor('#666')
              .margin({ bottom: 8 })
            
            TextInput({ text: this.serverUrl })
              .width('100%')
              .height(44)
              .backgroundColor('#F5F5F5')
              .borderRadius(8)
              .onChange((value) => {
                this.serverUrl = value
              })
          }
          .width('100%')
          .padding(16)
          .backgroundColor('#FFFFFF')
          .borderRadius(12)
          .margin({ bottom: 16 })

          // 简单SSE测试
          Column() {
            Row() {
              Text('简单流式测试')
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
              Blank()
              Text(this.simpleStatus)
                .fontSize(12)
                .fontColor(this.simpleStatus === '成功' ? '#4CAF50' : 
                          this.simpleStatus === '失败' ? '#F44336' : '#999')
            }
            .width('100%')
            .margin({ bottom: 12 })

            Text('测试逐字符流式响应（模拟LLM打字机效果）')
              .fontSize(12)
              .fontColor('#666')
              .margin({ bottom: 12 })

            // 结果显示区
            Column() {
              Text(this.simpleResult || '点击按钮开始测试...')
                .fontSize(14)
                .fontColor(this.simpleResult ? '#333' : '#999')
            }
            .width('100%')
            .height(100)
            .padding(12)
            .backgroundColor('#F5F5F5')
            .borderRadius(8)
            .margin({ bottom: 12 })

            Button(this.isSimpleTesting ? '测试中...' : '开始简单测试')
              .width('100%')
              .height(44)
              .backgroundColor(this.isSimpleTesting ? '#CCC' : '#2196F3')
              .enabled(!this.isSimpleTesting)
              .onClick(() => this.runSimpleTest())
          }
          .width('100%')
          .padding(16)
          .backgroundColor('#FFFFFF')
          .borderRadius(12)
          .margin({ bottom: 16 })

          // 词典SSE测试
          Column() {
            Row() {
              Text('词典流式测试')
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
              Blank()
              Text(this.dictStatus)
                .fontSize(12)
                .fontColor(this.dictStatus === '成功' ? '#4CAF50' : 
                          this.dictStatus === '失败' ? '#F44336' : '#999')
            }
            .width('100%')
            .margin({ bottom: 12 })

            Text('测试分阶段流式响应（释义→词性→例句→Tips）')
              .fontSize(12)
              .fontColor('#666')
              .margin({ bottom: 12 })

            // 结果显示区
            Column() {
              Text(this.dictResult || '点击按钮开始测试...')
                .fontSize(14)
                .fontColor(this.dictResult ? '#333' : '#999')
            }
            .width('100%')
            .height(150)
            .padding(12)
            .backgroundColor('#F5F5F5')
            .borderRadius(8)
            .margin({ bottom: 12 })

            Button(this.isDictTesting ? '测试中...' : '开始词典测试')
              .width('100%')
              .height(44)
              .backgroundColor(this.isDictTesting ? '#CCC' : '#4CAF50')
              .enabled(!this.isDictTesting)
              .onClick(() => this.runDictTest())
          }
          .width('100%')
          .padding(16)
          .backgroundColor('#FFFFFF')
          .borderRadius(12)

          // 说明
          Column() {
            Text('测试说明')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .margin({ bottom: 8 })
            
            Text('1. 简单测试：验证基本SSE流式接收能力')
              .fontSize(12)
              .fontColor('#666')
            Text('2. 词典测试：验证结构化JSON流式解析')
              .fontSize(12)
              .fontColor('#666')
            Text('3. 如果看到内容逐步显示，说明SSE支持正常')
              .fontSize(12)
              .fontColor('#666')
            Text('4. 如果一次性显示全部内容，说明可能不支持流式')
              .fontSize(12)
              .fontColor('#666')
          }
          .width('100%')
          .padding(16)
          .backgroundColor('#FFF8E1')
          .borderRadius(12)
          .margin({ top: 16 })
        }
        .width('100%')
        .padding(16)
      }
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F0F0F0')
  }

  /**
   * ArrayBuffer转字符串
   */
  private arrayBufferToString(buffer: ArrayBuffer): string {
    const textDecoder = util.TextDecoder.create('utf-8')
    const uint8Array = new Uint8Array(buffer)
    return textDecoder.decodeToString(uint8Array)
  }

  /**
   * 运行简单SSE测试
   * 使用http.createHttp() 尝试流式读取
   */
  runSimpleTest(): void {
    this.isSimpleTesting = true
    this.simpleResult = ''
    this.simpleStatus = '测试中'

    const url = `${this.serverUrl}/api/sse/test/simple`
    
    try {
      const httpRequest = http.createHttp()
      
      httpRequest.on('dataReceive', (data: ArrayBuffer) => {
        const text = this.arrayBufferToString(data)
        console.info(`SSE data received: ${text}`)
        
        // 解析SSE数据
        const lines = text.split('\n')
        for (let i = 0; i < lines.length; i++) {
          const line = lines[i]
          if (line.startsWith('data: ')) {
            const content = line.substring(6)
            if (content !== '[DONE]') {
              this.simpleResult += content
            }
          }
        }
      })

      httpRequest.on('dataEnd', () => {
        console.info('SSE stream ended')
        this.simpleStatus = this.simpleResult.length > 0 ? '成功' : '失败'
        this.isSimpleTesting = false
      })

      // 发起请求
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        header: {
          'Accept': 'text/event-stream',
          'Cache-Control': 'no-cache'
        },
        expectDataType: http.HttpDataType.STRING
      }

      // 使用requestInStream进行流式请求
      httpRequest.requestInStream(url, options, (err: BusinessError, data: number) => {
        if (err) {
          console.error(`SSE request error: ${JSON.stringify(err)}`)
          this.simpleStatus = '失败'
          this.simpleResult = `错误: ${err.message}`
          this.isSimpleTesting = false
        }
      })

    } catch (error) {
      const errMsg = error instanceof Error ? error.message : String(error)
      console.error(`SSE test error: ${errMsg}`)
      this.simpleStatus = '失败'
      this.simpleResult = `异常: ${errMsg}`
      this.isSimpleTesting = false
    }
  }

  /**
   * 运行词典SSE测试
   */
  runDictTest(): void {
    this.isDictTesting = true
    this.dictResult = ''
    this.dictStatus = '测试中'

    const url = `${this.serverUrl}/api/sse/test/dict`

    try {
      const httpRequest = http.createHttp()
      
      httpRequest.on('dataReceive', (data: ArrayBuffer) => {
        const text = this.arrayBufferToString(data)
        console.info(`SSE dict data: ${text}`)
        
        // 解析SSE数据
        const lines = text.split('\n')
        for (let i = 0; i < lines.length; i++) {
          const line = lines[i]
          if (line.startsWith('data: ')) {
            const content = line.substring(6)
            try {
              const json: SSEDictData = JSON.parse(content) as SSEDictData
              const type = json.type
              const value = json.content
              
              if (type === 'meaning' && typeof value === 'string') {
                this.dictResult += `释义: ${value}\n`
              } else if (type === 'word_type' && typeof value === 'string') {
                this.dictResult += `词性: ${value}\n`
              } else if (type === 'example' && value !== null && typeof value === 'object') {
                const example = value as SSEExampleData
                this.dictResult += `例句: ${example.ko}\n      ${example.zh}\n`
              } else if (type === 'tip' && typeof value === 'string') {
                this.dictResult += `Tips: ${value}\n`
              } else if (type === 'done') {
                this.dictResult += '\n[完成]'
              }
            } catch (e) {
              // 忽略解析错误
            }
          }
        }
      })

      httpRequest.on('dataEnd', () => {
        this.dictStatus = this.dictResult.length > 0 ? '成功' : '失败'
        this.isDictTesting = false
      })

      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        header: {
          'Accept': 'text/event-stream',
          'Cache-Control': 'no-cache'
        },
        expectDataType: http.HttpDataType.STRING
      }

      httpRequest.requestInStream(url, options, (err: BusinessError, data: number) => {
        if (err) {
          console.error(`SSE dict request error: ${JSON.stringify(err)}`)
          this.dictStatus = '失败'
          this.dictResult = `错误: ${err.message}`
          this.isDictTesting = false
        }
      })

    } catch (error) {
      const errMsg = error instanceof Error ? error.message : String(error)
      console.error(`SSE dict test error: ${errMsg}`)
      this.dictStatus = '失败'
      this.dictResult = `异常: ${errMsg}`
      this.isDictTesting = false
    }
  }
}
