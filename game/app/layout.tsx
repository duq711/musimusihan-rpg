import type { Metadata } from 'next';
import './globals.css';

export const metadata: Metadata = {
  metadataBase: new URL('https://echoes-sanctuary-rpg.duq711.chatgpt.site'),
  title: '잔향의 성소 | 판타지 공포 익스트랙션 RPG',
  description: '버튼으로 한 칸씩 던전을 탐색하고, 전투와 파밍을 거쳐 검은 성물함을 가지고 탈출하는 모바일 RPG 프로토타입.',
  alternates: {
    canonical: '/',
  },
  openGraph: {
    title: '잔향의 성소',
    description: '살아서 돌아와라. 고전 던전 이동과 익스트랙션 생존이 만난 판타지 공포 RPG.',
    type: 'website',
    images: [
      {
        url: 'https://echoes-sanctuary-rpg.duq711.chatgpt.site/og.png',
        width: 1731,
        height: 909,
        alt: '잔향의 성소 — 살아서 돌아와라',
      },
    ],
  },
  twitter: {
    card: 'summary_large_image',
    title: '잔향의 성소',
    description: '살아서 돌아와라. 판타지 공포 익스트랙션 RPG.',
    images: ['https://echoes-sanctuary-rpg.duq711.chatgpt.site/og.png'],
  },
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="ko">
      <body>{children}</body>
    </html>
  );
}
