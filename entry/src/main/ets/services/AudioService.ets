/**
 * 音频播放服务
 * 负责TTS语音播放
 * 适配 ArkTS 严格模式
 */
import media from '@ohos.multimedia.media';
import http from '@ohos.net.http';
import fs from '@ohos.file.fs';
import { API_BASE_URL, BIZ_API_PREFIX, APP_ID } from '../utils/Constants';
import ApiService from './ApiService';

class AudioService {
  private static instance: AudioService;
  private avPlayer: media.AVPlayer | null = null;
  private isPlaying: boolean = false;
  private currentText: string = '';
  private cacheDir: string = '';

  private constructor() {}

  static getInstance(): AudioService {
    if (!AudioService.instance) {
      AudioService.instance = new AudioService();
    }
    return AudioService.instance;
  }

  /**
   * 设置缓存目录
   */
  setCacheDir(dir: string) {
    this.cacheDir = dir;
    console.info(`AudioService: Cache dir set to ${dir}`);
  }

  /**
   * 播放韩语TTS
   */
  async playKorean(text: string): Promise<void> {
    await this.play(text, 'ko');
  }

  /**
   * 播放中文TTS
   */
  async playChinese(text: string): Promise<void> {
    await this.play(text, 'zh');
  }

  /**
   * 播放TTS音频
   */
  async play(text: string, lang: string = 'ko'): Promise<void> {
    if (!text || text.trim().length === 0) {
      console.warn('AudioService: Empty text, skip playing');
      return;
    }

    // 如果正在播放同一段文字，跳过
    if (this.isPlaying && this.currentText === text) {
      console.info('AudioService: Already playing this text');
      return;
    }

    // 停止当前播放
    await this.stop();

    this.currentText = text;
    this.isPlaying = true;

    console.info(`AudioService: Starting to play: ${text}`);

    try {
      // 下载音频文件并播放
      const audioData = await this.downloadAudio(text, lang);
      if (audioData && audioData.byteLength > 0) {
        console.info(`AudioService: Downloaded ${audioData.byteLength} bytes`);
        await this.playAudioData(audioData);
      } else {
        console.error('AudioService: Downloaded empty audio data');
        this.isPlaying = false;
      }
    } catch (error) {
      console.error('AudioService: Play failed', JSON.stringify(error));
      this.isPlaying = false;
    }
  }

  /**
   * 下载TTS音频
   */
  private async downloadAudio(text: string, lang: string): Promise<ArrayBuffer> {
    const url = `${API_BASE_URL}${BIZ_API_PREFIX}/api/tts/play?text=${encodeURIComponent(text)}&lang=${lang}`;
    console.info(`AudioService: Downloading from ${url}`);

    const apiService = ApiService.getInstance();
    const httpClient = http.createHttp();
    try {
      const authHeaders: Record<string, string> = {
        'X-App-Id': APP_ID,
      };
      const token = apiService.getToken();
      if (token) {
        authHeaders['Authorization'] = `Bearer ${token}`;
      }
      const deviceId = apiService.getDeviceId();
      if (deviceId) {
        authHeaders['X-Device-Id'] = deviceId;
      }

      const response = await httpClient.request(url, {
        method: http.RequestMethod.GET,
        header: authHeaders,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: 10000,
        readTimeout: 15000,
      });

      console.info(`AudioService: HTTP response code: ${response.responseCode}`);

      if (response.responseCode === 200) {
        return response.result as ArrayBuffer;
      } else {
        console.error(`AudioService: HTTP error ${response.responseCode}`);
        return new ArrayBuffer(0);
      }
    } catch (error) {
      console.error('AudioService: Download failed', JSON.stringify(error));
      return new ArrayBuffer(0);
    } finally {
      httpClient.destroy();
    }
  }

  /**
   * 播放音频数据
   */
  private async playAudioData(audioData: ArrayBuffer): Promise<void> {
    try {
      // 创建AVPlayer
      this.avPlayer = await media.createAVPlayer();
      console.info('AudioService: AVPlayer created');

      // 设置回调
      this.avPlayer.on('stateChange', (state: string) => {
        console.info(`AudioService: State changed to ${state}`);
        if (state === 'completed' || state === 'error' || state === 'stopped') {
          this.isPlaying = false;
        }
        if (state === 'initialized') {
          // 准备播放
          this.avPlayer?.prepare();
        }
        if (state === 'prepared') {
          // 开始播放
          this.avPlayer?.play();
        }
      });

      this.avPlayer.on('error', (err: Error) => {
        console.error('AudioService: Player error', err.message);
        this.isPlaying = false;
      });

      // 使用fdSrc方式播放（内存数据）
      // 需要先写入临时文件
      if (this.cacheDir) {
        const tempFile = `${this.cacheDir}/temp_audio_${Date.now()}.mp3`;
        const file = fs.openSync(tempFile, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
        fs.writeSync(file.fd, audioData);
        
        // 使用fdSrc播放
        this.avPlayer.fdSrc = {
          fd: file.fd,
          offset: 0,
          length: audioData.byteLength
        };
        
        console.info('AudioService: Set fdSrc, waiting for state change');
      } else {
        console.error('AudioService: Cache dir not set, cannot play');
        this.isPlaying = false;
      }

    } catch (error) {
      console.error('AudioService: PlayAudioData failed', JSON.stringify(error));
      this.isPlaying = false;
    }
  }

  /**
   * 停止播放
   */
  async stop(): Promise<void> {
    if (this.avPlayer) {
      try {
        await this.avPlayer.stop();
        await this.avPlayer.release();
      } catch (error) {
        console.warn('AudioService: Stop failed', JSON.stringify(error));
      }
      this.avPlayer = null;
    }
    this.isPlaying = false;
    this.currentText = '';
  }

  /**
   * 是否正在播放
   */
  getIsPlaying(): boolean {
    return this.isPlaying;
  }

  /**
   * 销毁服务
   */
  async destroy(): Promise<void> {
    await this.stop();
  }
}

export default AudioService;
